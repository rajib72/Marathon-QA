/**
* @author:        Raj Sekhar Mukherjee
* @dateModified:  2026-06-19

* @lastReviewed:  2026-06-19

* @description:   Batch class to allocate contract details either for a single
*                 specified InsurancePolicy or for all eligible InsurancePolicies
*                 based on their unprocessed funding records.
*

*                 Self-chaining behaviour: in Eligible mode the batch re-queues


*                 itself while there are still unprocessed Funding__c records AND


*                 real progress was made in the previous run.  A hard cap of


*                 MAX_ITERATIONS prevents runaway execution.

*/
public with sharing class BatchContractAllocation
implements Database.Batchable<sObject>, Database.Stateful {
    
    // ── Constants ────────────────────────────────────────────────────────
    public static final String  SINGLE_MODE     = 'Single';
    public static final String  ELIGIBLE_MODE   = 'Eligible';
    
    public static final Integer MAX_ITERATIONS  = 20; // absolute self-chain safety cap
    
    
    
    // ── Shared query fields (single source of truth for both query modes) ─
    
    
    private static final String INS_POLICY_FIELDS =
        
        
        'Id, Name, Program_Code__c, Client__c, Client_Program_Code__c, '
        
        
        + 'Lien_Holder__c, Lien_Holder__r.AccountNumber, '
        
        
        + 'Coverage_Level__c, Coverage_Level__r.Name, '
        
        
        + 'Product__c, Ins_Carrier__c, Original_State__c, '
        
        
        + 'Contract_Term_Months__c, Premium_Tax_Old__c, MBI_Seller_Commission__c, '
        
        
        + 'Reserve__c, Written_Reserve__c, Reinstatement_Date__c, '
        
        
        + 'Options_Cost__c, Surcharge_Cost__c, Allocation_Expense_Amount__c, '
        
        
        + 'Sale_Date__c, DLRS_Total_Funded_Amount_from_Funding__c, '
        
        
        + 'Admin_Cost__c, Agent_Commision__c, ARF_Fee__c, '
        
        
        + 'Broker_Commission__c, Ceding_Fee2__c, CLIP__c, '
        
        
        + 'Fulfillment_Fee__c, Maintenance_Admin_Fee__c, Obligor_Fee__c, '
        
        
        + 'Offset_Surplus__c, Premium_Refund__c, Premium_Tax1__c, '
        
        
        + 'Processing_Fee__c, Reserve_Pack__c, Retention_Collection_Fee__c, '
        
        
        + 'Roadside_Fee2__c, Seller_Commission__c, System_Fee__c, '
        
        
        + 'Option_1__c, Legacy_Source__c, OT_Allocation__c, '
        
        
        + 'Funded_Admin_Fee__c, Funded_Agent_Commission__c, Funded_ARF_Fee__c, '
        
        
        + 'Funded_Broker_Commission__c, Funded_Ceding_Fee__c, Funded_CLIP_Fee__c, '
        
        
        + 'Funded_Fulfillment_Fee__c, Funded_Maintenance_Admin_Fee__c, '
        
        
        + 'Funded_Obligor_Fee__c, Funded_Obligor_Tax__c, Funded_Offset_Surplus__c, '
        
        
        + 'Funded_Premium_Refund__c, Funded_Premium_Tax__c, Funded_Processing_Fee__c, '
        
        
        + 'Funded_Reserve_Pack__c, Funded_Retention_Collection_Fee__c, '
        
        
        + 'Funded_Roadside_Fee__c, Funded_Seller_Commission__c, '
        
        
        + 'Funded_System_Fee__c, Funded_Reserve__c';
    
    
    // ── Subquery used by both modes — single source of truth ──────────────
    
    private static final String UNPROCESSED_SUBQUERY =
        
        
        'Id IN (SELECT Contract__c FROM Funding__c WHERE Time_Processed__c = null)';
    
    
    // ── Instance state (Database.Stateful) ────────────────────────────────
    
    @TestVisible private Boolean isSingleMode           = false;
    
    
    @TestVisible private Id      targetContract         = null;
    
    
    @TestVisible private Integer processedContractsCount = 0;
    
    
    @TestVisible private Integer previousRemainingCount  = -1; // -1 = first run sentinel
    
    
    @TestVisible private Integer iterationCount          = 0;
    
    
    // ── Custom exception ──────────────────────────────────────────────────
    public class OtherException extends Exception {}
    
    // ─────────────────────────────────────────────────────────────────────
    /**
* Backward-compatible 2-arg constructor. Starts a fresh chain (iteration 0).
* @param mode             'Single' or 'Eligible'.
* @param targetContractId Id of the InsurancePolicy when mode = 'Single'.
*/
    public BatchContractAllocation(String mode, Id targetContractId) {
        this(mode, targetContractId, -1, 0);
    }
    
    /**
* Full 4-arg constructor used internally for self-chaining.
* @param mode                   'Single' or 'Eligible'.
* @param targetContractId       Id of the InsurancePolicy when mode = 'Single'.
* @param previousRemainingCount Unprocessed Funding count from the previous run.
*                               Pass -1 on the first invocation.
* @param iterationCount         Number of times this batch has already chained.
*/
    public BatchContractAllocation(
        String  mode,
        Id      targetContractId,
        Integer previousRemainingCount,
        Integer iterationCount) {
            
            if (String.isNotEmpty(mode) && mode.equalsIgnoreCase(SINGLE_MODE)) {
                isSingleMode = true;
                SObjectType soType = targetContractId.getSObjectType();
                if (soType.getDescribe().getName() != 'InsurancePolicy') {
                    throw new OtherException(
                        'targetContractId must be an InsurancePolicy record Id.'
                    );
                }
                this.targetContract = targetContractId;
            }
            
            this.previousRemainingCount = previousRemainingCount;
            this.iterationCount         = iterationCount;
        }
    
    // ─────────────────────────────────────────────────────────────────────
    /**
* Builds the SOQL query for the batch scope.
* Single mode : targets one specific InsurancePolicy.
* Eligible mode: targets all contracts that still have unprocessed Funding__c
*                records, determined exclusively by Time_Processed__c = null
*                (no DLRS dependency — DLRS updates asynchronously and would
*                cause false exclusions while the rollup is stale).
*/
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query;
        
        if (isSingleMode) {
            query = 'SELECT ' + INS_POLICY_FIELDS
                + ' FROM InsurancePolicy'
                + ' WHERE Id = :targetContract'
                + ' AND Client__c != null'
                + ' AND ' + UNPROCESSED_SUBQUERY;
        } else {
            //    DLRS filter removed: the subquery is always consistent.
            //    DLRS_Total_Unprocessed_Funding__c is asynchronous and can exclude
            //    records that legitimately have Time_Processed__c = null during lag.
            query = 'SELECT ' + INS_POLICY_FIELDS
                + ' FROM InsurancePolicy'
                + ' WHERE Client__c != null'
                + ' AND ' + UNPROCESSED_SUBQUERY;
        }
        
        return Database.getQueryLocator(query);
    }
    
    // ─────────────────────────────────────────────────────────────────────
    /**
* Processes each batch of InsurancePolicy records.
* The contract count is incremented only on successful execution.
*/
    public void execute(Database.BatchableContext bc, List<InsurancePolicy> insPolicyList) {
        try {
            if (!insPolicyList.isEmpty()) {
                ContractAllocationUtilityCtrl.splitContractsByClient(insPolicyList);
                // Increment only after successful execution, not before.
                //    If splitContractsByClient throws, we do not count these records.
                processedContractsCount += insPolicyList.size();
            }
        } catch (Exception e) {
            // Use consistent lowercase 'bc' — Apex is case-insensitive but
            //    convention requires camelCase local variables throughout.
            QDX_Log.publishLog(
                UtilityClass.formatBatchErrorMessage(e, bc.getJobId()),
                'BatchContractAllocation', 'ERROR', bc.getJobId()
            );
        }
    }
    
    // ─────────────────────────────────────────────────────────────────────
    /**
* Determines whether to self-chain, stop, or hand off to BatchRopAllocation.
*
* Self-chain conditions (all must be true):
*   1. Eligible mode (not Single).
*   2. Records were processed this run (processedContractsCount > 0).
*   3. Unprocessed Funding__c records still exist.
*   4. The count decreased vs. the previous run (real progress was made).
*   5. The iteration cap has not been reached.
*   6. No other BatchContractAllocation job is already queued/running.
*/
    public void finish(Database.BatchableContext bc) {
        
        // Query Funding__c directly — Time_Processed__c is always real-time.
        //    Avoids DLRS staleness and mismatched field criteria vs. start().
        Integer remainingUnprocessed = [
            SELECT COUNT()
            FROM   Funding__c
            WHERE  Time_Processed__c = null
        ];
        
        QDX_LOG.debug(
            'BatchContractAllocation.finish()'
            + ' | Remaining unprocessed Funding: ' + remainingUnprocessed
            + ' | Processed this run: '          + processedContractsCount
            + ' | Previous remaining: '          + previousRemainingCount
            + ' | Iteration: '                   + iterationCount
        );
        QDX_LOG.publish();
        
        if (remainingUnprocessed > 0 && processedContractsCount > 0 && !isSingleMode) {
            
            Boolean madeProgress      = (previousRemainingCount == -1)
                || (remainingUnprocessed < previousRemainingCount);
            Boolean underIterationCap = (iterationCount < MAX_ITERATIONS);
            
            if (madeProgress && underIterationCap) {
                
                List<AsyncApexJob> runningJobs = [
                    SELECT Id
                    FROM   AsyncApexJob
                    WHERE  ApexClass.Name = 'BatchContractAllocation'
                    AND    Status IN ('Holding', 'Preparing', 'Processing', 'Queued')
                    LIMIT 1
                ];
                
                if (runningJobs.isEmpty()) {
                    Database.executeBatch(
                        new BatchContractAllocation(
                            ELIGIBLE_MODE, null,
                            remainingUnprocessed,   // pass current count as next "previous"
                            iterationCount + 1
                        ),
                        3
                    );
                }
                
            } else {
                String stopReason = !madeProgress
                    ? 'No progress made — remaining count unchanged ('
                    + previousRemainingCount + ' → ' + remainingUnprocessed + '). '
                    + 'Records may require manual investigation.'
                    : 'Maximum iteration cap (' + MAX_ITERATIONS + ') reached.';
                QDX_LOG.debug('BatchContractAllocation stopping self-chain: ' + stopReason);
                QDX_LOG.publish();
            }
            
            return; // do NOT launch BatchRopAllocation until all funding is done
        }
        
        // All funding processed (or single-mode run complete) — hand off.
        if (Test.isRunningTest()) { return; }
        
        List<AsyncApexJob> runningRopJobs = [
            SELECT Id
            FROM   AsyncApexJob
            WHERE  ApexClass.Name = 'BatchRopAllocation'
            AND    Status IN ('Holding', 'Preparing', 'Processing', 'Queued')
            LIMIT 1
        ];
        
        if (runningRopJobs.isEmpty()) {
            ROPAllocationOrchestrator.startAllocation();
        }
    }
}