public class OpportunityTriggerHandler extends TriggerHandler {
    private static final String STAGE_CHANGED_TO_CLOSED_WON = 'Stage changed to Closed Won';

    // Override for before insert logic
    protected override void beforeInsert() {
        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            // Set default Type for new Opportunities
            if (opp.Type == null) {
                opp.Type = 'New Customer';
            }
        }
    }

    // Override for before update logic
    protected override void beforeUpdate() {
        Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>(Trigger.old);

        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            Opportunity oldOpp = oldOppMap.get(opp.Id);

            // Ensure amount is greater than 5000
            if (opp.Amount < 5000) {
                opp.Amount.addError('Opportunity amount should be greater than 5000.');
            }
        }
    }

    // Override for after insert logic
    protected override void afterInsert() {
        List<Task> tasksToInsert = new List<Task>();

        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            // Create a new task for new Opportunities
            Task newTask = new Task(
                Subject = 'Follow up on new Opportunity',
                WhatId = opp.Id
            );
            tasksToInsert.add(newTask);
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    // Override for after update logic
    protected override void afterUpdate() {
        List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        List<Task> tasksToInsert = new List<Task>();

        Map<Id, Opportunity> oldOppMap = new Map<Id, Opportunity>(Trigger.old);

        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            Opportunity oldOpp = oldOppMap.get(opp.Id);

            // Check if stage has changed to 'Closed Won'
            if (opp.StageName == 'Closed Won' && oldOpp.StageName!= 'Closed Won') {
                opportunitiesToUpdate.add(opp);

                // Create a new task for 'Closed Won' Opportunities
                Task newTask = new Task(
                    Subject = STAGE_CHANGED_TO_CLOSED_WON,
                    WhatId = opp.Id
                );
                tasksToInsert.add(newTask);
            }
        }

        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }
}



