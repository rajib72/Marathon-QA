/**
 * @description
 * QA-only native OmniScript dependent Select POC.
 *
 * Supports Callable and VlocityOpenInterface.
 * Includes diagnostic logging for OmniScript invocation.
 *
 * No SOQL, DML, callouts, or BRE dependencies.
 *
 * IMPORTANT:
 * Values are demonstration data, NOT Rate Set data.
 */
global with sharing class ReRatePicklistPocProvider
    implements omnistudio.VlocityOpenInterface, Callable {

    /**
     * Salesforce Callable entry point.
     */
    global Object call(
        String action,
        Map<String, Object> args
    ) {

        // DEBUG: Identify Callable invocation
        System.debug(
            LoggingLevel.WARN,
            'RERATE_POC_CALLED_ACTION=' + action
        );

        if (args == null || String.isBlank(action)) {
            return false;
        }

        Map<String, Object> input =
            (Map<String, Object>) args.get('input');

        Map<String, Object> output =
            (Map<String, Object>) args.get('output');

        Map<String, Object> options =
            (Map<String, Object>) args.get('options');

        return invokeMethod(
            action,
            input,
            output,
            options
        );
    }

    /**
     * OmniStudio method dispatcher.
     */
    global Boolean invokeMethod(
        String methodName,
        Map<String, Object> input,
        Map<String, Object> outMap,
        Map<String, Object> options
    ) {

        // DEBUG: Identify OmniStudio method invocation
        System.debug(
            LoggingLevel.WARN,
            'RERATE_POC_INVOKE_METHOD=' + methodName
        );

        if (
            String.isBlank(methodName) ||
            outMap == null
        ) {
            return false;
        }

        if (methodName == 'getTermMonths') {

            populateTermMonths(
                input,
                outMap,
                options
            );

            return true;
        }

        if (methodName == 'getTermMiles') {

            populateTermMiles(
                input,
                outMap,
                options
            );

            return true;
        }

        if (methodName == 'getTermMilesFlatDebug') {

            // DEBUG: Confirm flat child option invocation
            System.debug(
                LoggingLevel.WARN,
                'RERATE_POC_FLAT_MILES_METHOD_EXECUTED'
            );

            outMap.put(
                'options',
                buildTermMilesDependency().get('12')
            );

            System.debug(
                LoggingLevel.WARN,
                'RERATE_POC_FLAT_MILES_OUTPUT=' +
                JSON.serialize(outMap)
            );

            return true;
        }

        System.debug(
            LoggingLevel.WARN,
            'RERATE_POC_UNKNOWN_ACTION=' + methodName
        );

        return false;
    }

    /**
     * Parent Select options.
     */
    private void populateTermMonths(
        Map<String, Object> input,
        Map<String, Object> outMap,
        Map<String, Object> options
    ) {

        List<Map<String, String>> picklist =
            new List<Map<String, String>>();

        picklist.add(
            option('12', '12 months')
        );

        picklist.add(
            option('24', '24 months')
        );

        picklist.add(
            option('36', '36 months')
        );

        outMap.put('options', picklist);

        System.debug(
            LoggingLevel.WARN,
            'POC_TERM_MONTHS_OUTPUT=' +
            JSON.serialize(outMap)
        );
    }

    /**
     * Dependent Select options.
     *
     * Keys must match the controlling Select's
     * language-independent name values.
     */
    private void populateTermMiles(
        Map<String, Object> input,
        Map<String, Object> outMap,
        Map<String, Object> options
    ) {

        Map<String, List<Map<String, String>>>
            dependency = buildTermMilesDependency();

        outMap.put(
            'dependency',
            dependency
        );

        System.debug(
            LoggingLevel.WARN,
            'POC_TERM_MILES_INPUT=' +
            JSON.serialize(input)
        );

        System.debug(
            LoggingLevel.WARN,
            'POC_TERM_MILES_OUTPUT=' +
            JSON.serialize(outMap)
        );
    }

    /**
     * All possible dependent values.
     */
    private static Map<String, List<Map<String, String>>>
        buildTermMilesDependency() {

        Map<String, List<Map<String, String>>>
            dependency =
                new Map<String,
                    List<Map<String, String>>>();

        dependency.put(
            '12',
            new List<Map<String, String>> {
                option('12000', '12,000 miles'),
                option('24000', '24,000 miles')
            }
        );

        dependency.put(
            '24',
            new List<Map<String, String>> {
                option('24000', '24,000 miles'),
                option('36000', '36,000 miles')
            }
        );

        dependency.put(
            '36',
            new List<Map<String, String>> {
                option('36000', '36,000 miles'),
                option('60000', '60,000 miles')
            }
        );

        return dependency;
    }

    /**
     * OmniScript option name/value pair.
     */
    private static Map<String, String> option(
        String apiValue,
        String displayLabel
    ) {

        return new Map<String, String> {
            'name'  => apiValue,
            'value' => displayLabel
        };
    }
}