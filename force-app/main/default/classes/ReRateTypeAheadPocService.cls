/**
 * Phase 1B - QA-only, read-only Type Ahead Lookup POC.
 * No SOQL, DML, callouts, or coupling to Open ReRate / BRE.
 * All values are ILLUSTRATIVE, not real Rate Set data.
 */
global with sharing class ReRateTypeAheadPocService
    implements omnistudio.VlocityOpenInterface, Callable {

    global Object call(String action, Map<String, Object> args) {
        System.debug(LoggingLevel.WARN, 'RERATE_POC1B_CALL=' + action);
        if (args == null) return false;
        return invokeMethod(
            action,
            (Map<String, Object>) args.get('input'),
            (Map<String, Object>) args.get('output'),
            (Map<String, Object>) args.get('options')
        );
    }

    global Boolean invokeMethod(
        String methodName,
        Map<String, Object> inputMap,
        Map<String, Object> outMap,
        Map<String, Object> options
    ) {
        System.debug(LoggingLevel.WARN, 'RERATE_POC1B_METHOD=' + methodName);
        if (methodName != 'getMileageChoices' || outMap == null) return false;

        String selectedMonths = resolveMonths(inputMap);
        List<Map<String, String>> records = new List<Map<String, String>>();

        if (selectedMonths == '12') {
            records.add(choice('12000', '12,000 miles'));
            records.add(choice('24000', '24,000 miles'));
        } else if (selectedMonths == '24') {
            records.add(choice('24000', '24,000 miles'));
            records.add(choice('36000', '36,000 miles'));
        } else if (selectedMonths == '36') {
            records.add(choice('36000', '36,000 miles'));
            records.add(choice('60000', '60,000 miles'));
        }

        // Root-level list consumed by the Type Ahead Block's Data JSON Path.
        outMap.put('PocMilesChoices', records);
        outMap.put('PocSelectedMonths', selectedMonths);
        outMap.put('PocLookupMessage', records.isEmpty()
            ? 'Select a supported Contract Term Months value (12, 24 or 36).'
            : 'OK');

        System.debug(LoggingLevel.WARN,
            'RERATE_POC1B_OUTPUT=' + JSON.serialize(outMap));
        return true;
    }

    private static String resolveMonths(Map<String, Object> inputMap) {
        if (inputMap == null) return null;
        // Preferred: Remote Action Additional Input: termMonths = %POC_MonthsStep:POC_TermMonths%
        Object direct = inputMap.get('termMonths');
        if (direct == null) direct = inputMap.get('POC_TermMonths');
        if (direct != null) return String.valueOf(direct).trim();

        // Fallback when the action sends the entire OmniScript Data JSON.
        for (String nodeName : new List<String>{ 'POC_MonthsStep', 'POC_SelectStep' }) {
            Object node = inputMap.get(nodeName);
            if (node != null && node instanceof Map<String, Object>) {
                Map<String, Object> nested = (Map<String, Object>) node;
                Object months = nested.get('POC_TermMonths');
                if (months != null) return String.valueOf(months).trim();
            }
        }
        return null;
    }

    private static Map<String, String> choice(String mileage, String label) {
        return new Map<String, String>{
            'MileageValue' => mileage,
            'MileageLabel' => label
        };
    }
}