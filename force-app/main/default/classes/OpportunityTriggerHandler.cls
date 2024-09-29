public class OpportunityTriggerHandler extends TriggerHandler {
    private static Boolean isFirstRun = true;
    private static Set<Id> processedOppIds = new Set<Id>();

    // Handle before insert logic
    @TestVisible
    protected override void beforeInsert() {
        // Cast Trigger.new to List<Opportunity>
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            // Set default Type for new Opportunities
            if (opp.Type == null) {
                opp.Type = 'New Customer';
            }
        }
    }

    // Handle before update logic
    @TestVisible
    protected override void beforeUpdate() {
        // Validate that the amount is greater than 5000
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if (opp.Amount < 5000) {
                opp.addError('Opportunity amount must be greater than 5000');
            }
        }
        
        // Handle Stage change description update
        Map<Id, Opportunity> oldOppMap = (Map<Id, Opportunity>) Trigger.oldMap;
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            Opportunity oldOpp = oldOppMap.get(opp.Id);
            if (opp.StageName != oldOpp.StageName) {
                opp.Description = (opp.Description == null ? '' : opp.Description) + 
                    '\nStage Change: ' + opp.StageName + ': ' + DateTime.now().format();
            }
        }

        // Set the primary contact to the 'CEO' if not already set
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            accountIds.add(opp.AccountId);
        }
        
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO']);
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if (opp.Primary_Contact__c == null && contacts.containsKey(opp.AccountId)) {
                opp.Primary_Contact__c = contacts.get(opp.AccountId).Id;
            }
        }
    }

    // Handle before delete logic
    @TestVisible
    protected override void beforeDelete() {
        // Prevent deletion of closed won opportunities for banking accounts
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Industry FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Id IN :Trigger.old)]);
        for (Opportunity opp : (List<Opportunity>) Trigger.old) {
            if (opp.StageName == 'Closed Won' && accounts.get(opp.AccountId).Industry == 'Banking') {
                opp.addError('Cannot delete a closed won opportunity for a banking account');
            }
            // Prevent deletion of closed opportunities
            if (opp.IsClosed) {
                opp.addError('Cannot delete closed opportunity');
            }
        }
    }

    // Handle after insert logic
    @TestVisible
    protected override void afterInsert() {
        // Create tasks for newly inserted opportunities
        List<Task> tasksToInsert = new List<Task>();
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if (!processedOppIds.contains(opp.id)) {
            Task tsk = new Task();
            tsk.Subject = 'Call Primary Contact';
            tsk.WhatId = opp.Id;
            tsk.WhoId = opp.Primary_Contact__c;
            tsk.OwnerId = opp.OwnerId;
            tsk.ActivityDate = Date.today().addDays(3);
            tasksToInsert.add(tsk);
            processedOppIds.add(opp.Id);
                }
            }
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    // Handle after delete logic
    @TestVisible
    protected override void afterDelete() {
        notifyOwnersOpportunityDeleted((List<Opportunity>) Trigger.old);
    }

    // Handle after undelete logic
    @TestVisible
    protected override void afterUndelete() {
        assignPrimaryContact((Map<Id, Opportunity>) Trigger.newMap);
    }

    // Helper method to notify owners of deleted opportunities
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

    // Helper method to assign the primary contact for undeleted opportunities
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





