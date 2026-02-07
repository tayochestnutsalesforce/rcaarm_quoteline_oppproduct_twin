/**
 * @description Unit tests for TwinFieldMappingController.
 */
@IsTest
private class TwinFieldMappingControllerTest {
    @IsTest
    static void testGetFieldOptions() {
        TwinFieldMappingController.FieldOptionsResponse response =
            TwinFieldMappingController.getFieldOptions();
        System.assertNotEquals(null, response, 'Field options response should not be null.');
        System.assertNotEquals(null, response.sourceFields, 'Source fields should not be null.');
        System.assertNotEquals(null, response.targetFields, 'Target fields should not be null.');
    }

    @IsTest
    static void testSaveMappingsSuccessOrFailure() {
        FieldPair pair = findMatchingCustomFields();
        TwinFieldMappingController.MappingInput input = new TwinFieldMappingController.MappingInput();
        input.label = 'Test Mapping';
        input.sourceField = pair == null ? 'Bad__c' : pair.sourceField;
        input.targetField = pair == null ? 'Bad__c' : pair.targetField;
        input.overwriteRule = 'Always';
        input.transform = 'None';
        input.isActive = true;

        TwinFieldMappingController.SaveResultDto result =
            TwinFieldMappingController.saveMappings(
                new List<TwinFieldMappingController.MappingInput>{ input },
                new List<Id>()
            );

        System.assertNotEquals(null, result, 'Save result should not be null.');
        if (pair == null) {
            System.assert(
                result.statusText.startsWith('Failed:'),
                'Expected failure when no valid custom fields exist.'
            );
        } else {
            System.assertEquals('Success', result.statusText, 'Expected success status.');
            List<TwinFieldMapConfig__c> records = [
                SELECT Id, Name
                FROM TwinFieldMapConfig__c
                WHERE Name = :input.label
                LIMIT 1
            ];
            System.assertEquals(1, records.size(), 'Mapping record should be created.');
        }
    }

    @IsTest
    static void testSaveMappingsDelete() {
        FieldPair pair = findMatchingCustomFields();
        if (pair == null) {
            return;
        }

        TwinFieldMapConfig__c record = new TwinFieldMapConfig__c(
            Name = 'Delete Me',
            SourceObject__c = 'QuoteLineItem',
            SourceField__c = pair.sourceField,
            TargetObject__c = 'OpportunityLineItem',
            TargetField__c = pair.targetField,
            OverwriteRule__c = 'Always',
            Transform__c = 'None',
            IsActive__c = true
        );
        insert record;

        TwinFieldMappingController.SaveResultDto result =
            TwinFieldMappingController.saveMappings(
                new List<TwinFieldMappingController.MappingInput>(),
                new List<Id>{ record.Id }
            );

        System.assertEquals('Success', result.statusText, 'Expected success status on delete.');
        AggregateResult[] results = [
            SELECT count(Id) recordCount
            FROM TwinFieldMapConfig__c
            WHERE Id = :record.Id
        ];
        Integer countValue = (Integer)results[0].get('recordCount');
        System.assertEquals(0, countValue, 'Record should be deleted.');
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
