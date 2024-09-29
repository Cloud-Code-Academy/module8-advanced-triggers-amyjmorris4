/*
AnotherOpportunityTrigger Overview

This trigger was initially created for handling various events on the Opportunity object. It was developed by a prior developer and has since been noted to cause some issues in our org.

IMPORTANT:
- This trigger does not adhere to Salesforce best practices.
- It is essential to review, understand, and refactor this trigger to ensure maintainability, performance, and prevent any inadvertent issues.

ISSUES:
Avoid nested for loop - 1 instance - found
Avoid DML inside for loop - 1 instance - found
Bulkify Your Code - 1 instance
Avoid SOQL Query inside for loop - 2 instances - found
Stop recursion - 1 instance

RESOURCES: 
https://www.salesforceben.com/12-salesforce-apex-best-practices/
https://developer.salesforce.com/blogs/developer-relations/2015/01/apex-best-practices-15-apex-commandments
*/

//Since the logic from AnotherOpportunityTrigger has been moved to the AccountHelper class, this trigger is no longer needed.

trigger AnotherOpportunityTrigger on Opportunity (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    
    if (AnotherOpportunityTriggerHelper.isFirstRun) {
        AnotherOpportunityTriggerHelper.isFirstRun = false;
        
        if (Trigger.isBefore) {
            if (Trigger.isInsert) {
                // Set default Type for new Opportunities
                for (Opportunity opp : Trigger.new) {
                    if (opp.Type == null) {
                        opp.Type = 'New Customer';
                    }
                }
            } else if (Trigger.isDelete) {
                // Prevent deletion of closed Opportunities
                for (Opportunity oldOpp : Trigger.old) {
                    if (oldOpp.IsClosed) {
                        oldOpp.addError('Cannot delete closed opportunity');
                    }
                }
            } else if (Trigger.isUpdate) {
                // Move stage change logic to before update
                Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>(Trigger.old);
                for (Opportunity opp : Trigger.new) {
                    Opportunity oldOpp = oldOppMap.get(opp.Id);
                    if (opp.StageName != oldOpp.StageName) {
                        opp.Description = (opp.Description == null ? '' : opp.Description) + 
                            '\nStage Change: ' + opp.StageName + ': ' + DateTime.now().format();
                    }
                }
            }
        }

        if (Trigger.isAfter) {
            if (Trigger.isInsert) {
                // Create Tasks for newly inserted Opportunities
                List<Task> tasksToInsert = new List<Task>();
                for (Opportunity opp : Trigger.new) {
                    Task tsk = new Task();
                    tsk.Subject = 'Call Primary Contact';
                    tsk.WhatId = opp.Id;
                    tsk.WhoId = opp.Primary_Contact__c;
                    tsk.OwnerId = opp.OwnerId;
                    tsk.ActivityDate = Date.today().addDays(3);
                    tasksToInsert.add(tsk);
                }
                if (!tasksToInsert.isEmpty()) {
                    insert tasksToInsert;
                }
            }

            // Notify owners of deleted Opportunities
            if (Trigger.isDelete) {
                notifyOwnersOpportunityDeleted(Trigger.old);
            }

            // Assign the primary contact to undeleted Opportunities
            if (Trigger.isUndelete) {
                assignPrimaryContact(Trigger.newMap);
            }
        }
        
        AnotherOpportunityTriggerHelper.isFirstRun = true;
    }

    
    public static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : opps) {
            ownerIds.add(opp.OwnerId);
        }

        Map<Id, User> userMap = new Map<Id, User>([SELECT Id, Email FROM User WHERE Id IN :ownerIds]);
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : opps) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            String[] toAddresses = new String[] { userMap.get(opp.OwnerId).Email };
            mail.setToAddresses(toAddresses);
            mail.setSubject('Opportunity Deleted : ' + opp.Name);
            mail.setPlainTextBody('Your Opportunity: ' + opp.Name + ' has been deleted.');
            mails.add(mail);
        }

        if (!mails.isEmpty()) {
            try {
                Messaging.sendEmail(mails);
            } catch (Exception e) {
                System.debug('Exception: ' + e.getMessage());
            }
        }
    }

    public static void assignPrimaryContact(Map<Id, Opportunity> oppNewMap) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : oppNewMap.values()) {
            if (opp.AccountId != null && opp.Primary_Contact__c == null) {
                accountIds.add(opp.AccountId);
            }
        }

        Map<Id, Contact> contactMap = new Map<Id, Contact>([
            SELECT Id, AccountId FROM Contact WHERE Title = 'VP Sales' AND AccountId IN :accountIds
        ]);

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        for (Opportunity opp : oppNewMap.values()) {
            Contact primaryContact = contactMap.get(opp.AccountId);
            if (opp.Primary_Contact__c == null && primaryContact != null) {
                opp.Primary_Contact__c = primaryContact.Id;
                oppsToUpdate.add(opp);
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }
}


