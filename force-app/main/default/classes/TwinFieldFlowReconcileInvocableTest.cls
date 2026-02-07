/**
 * @description Unit tests for TwinFieldFlowReconcileInvocable.
 */
@IsTest
private class TwinFieldFlowReconcileInvocableTest {
    @IsTest
    static void testReconcileNoInput() {
        List<TwinFieldFlowReconcileInvocable.Response> responses =
            TwinFieldFlowReconcileInvocable.reconcile(
                new List<TwinFieldFlowReconcileInvocable.Request>()
            );
        System.assertEquals(1, responses.size(), 'Expected one response.');
        System.assertEquals('Failed', responses[0].statusText, 'Expected failure status.');
        System.assertEquals(
            'No input provided.',
            responses[0].errorText,
            'Expected no input error.'
        );
    }

    @IsTest
    static void testReconcileSuccessOrFailure() {
        FieldPair pair = findMatchingCustomFields();
        TwinFieldMappingController.MappingInput input = new TwinFieldMappingController.MappingInput();
        input.label = 'Reconcile Mapping';
        input.sourceField = pair == null ? 'Bad__c' : pair.sourceField;
        input.targetField = pair == null ? 'Bad__c' : pair.targetField;
        input.overwriteRule = 'Always';
        input.transform = 'None';
        input.isActive = true;

        String mappingsJson = JSON.serialize(
            new List<TwinFieldMappingController.MappingInput>{ input }
        );
        TwinFieldFlowReconcileInvocable.Request request =
            new TwinFieldFlowReconcileInvocable.Request();
        request.mappingsJson = mappingsJson;
        request.deletedIdsJson = JSON.serialize(new List<Id>());

        List<TwinFieldFlowReconcileInvocable.Response> responses =
            TwinFieldFlowReconcileInvocable.reconcile(
                new List<TwinFieldFlowReconcileInvocable.Request>{ request }
            );

        System.assertEquals(1, responses.size(), 'Expected one response.');
        if (pair == null) {
            System.assertEquals('Failed', responses[0].statusText, 'Expected failure status.');
            System.assertNotEquals(null, responses[0].errorText, 'Expected error text.');
        } else {
            System.assertEquals('Success', responses[0].statusText, 'Expected success status.');
        }
    }

    private class FieldPair {
        public String sourceField;
        public String targetField;
    }

    private static FieldPair findMatchingCustomFields() {
        Map<Schema.DisplayType, String> sourceFields =
            getCustomFieldsByType(QuoteLineItem.SObjectType);
        Map<Schema.DisplayType, String> targetFields =
            getCustomFieldsByType(OpportunityLineItem.SObjectType);

        for (Schema.DisplayType typeValue : sourceFields.keySet()) {
            if (targetFields.containsKey(typeValue)) {
                FieldPair pair = new FieldPair();
                pair.sourceField = sourceFields.get(typeValue);
                pair.targetField = targetFields.get(typeValue);
                return pair;
            }
        }
        return null;
    }

    private static Map<Schema.DisplayType, String> getCustomFieldsByType(
        Schema.SObjectType sObjectType
    ) {
        Map<Schema.DisplayType, String> results = new Map<Schema.DisplayType, String>();
        Map<String, Schema.SObjectField> fields = sObjectType.getDescribe().fields.getMap();
        for (Schema.SObjectField field : fields.values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            String nameValue = describe.getName();
            if (nameValue == null) {
                continue;
            }
            if (!(nameValue.endsWith('__c')
                || nameValue.endsWith('__x')
                || nameValue.endsWith('__pc')
                || nameValue.endsWith('__s'))) {
                continue;
            }
            if (!results.containsKey(describe.getType())) {
                results.put(describe.getType(), describe.getName());
            }
        }
        return results;
    }
}
