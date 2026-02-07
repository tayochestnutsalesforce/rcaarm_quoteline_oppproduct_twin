/**
 * @description Controller for mapping admin UI and persistence.
 */
public with sharing class TwinFieldMappingController {
    private static final String SOURCE_OBJECT = 'QuoteLineItem';
    private static final String TARGET_OBJECT = 'OpportunityLineItem';
    private static final Set<Schema.DisplayType> SUPPORTED_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.String,
        Schema.DisplayType.TextArea,
        Schema.DisplayType.Email,
        Schema.DisplayType.Phone,
        Schema.DisplayType.Url,
        Schema.DisplayType.Double,
        Schema.DisplayType.Currency,
        Schema.DisplayType.Integer,
        Schema.DisplayType.Percent,
        Schema.DisplayType.Boolean,
        Schema.DisplayType.Date,
        Schema.DisplayType.DateTime
    };

    public class FieldOption {
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String dataType;
    }

    public class FieldOptionsResponse {
        @AuraEnabled public List<FieldOption> sourceFields;
        @AuraEnabled public List<FieldOption> targetFields;
    }

    public class MappingDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String sourceField;
        @AuraEnabled public String targetField;
        @AuraEnabled public String overwriteRule;
        @AuraEnabled public String transform;
        @AuraEnabled public Boolean isActive;
    }

    public class MappingInput {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String sourceField;
        @AuraEnabled public String targetField;
        @AuraEnabled public String overwriteRule;
        @AuraEnabled public String transform;
        @AuraEnabled public Boolean isActive;
    }

    public class SaveResultDto {
        @AuraEnabled public String statusText;
    }

    public class MappingValidationException extends Exception {}


    @AuraEnabled(cacheable=true)
    public static FieldOptionsResponse getFieldOptions() {
        FieldOptionsResponse response = new FieldOptionsResponse();
        response.sourceFields = buildFieldOptions(QuoteLineItem.SObjectType, true);
        response.targetFields = buildFieldOptions(OpportunityLineItem.SObjectType, false);
        return response;
    }

    @AuraEnabled(cacheable=true)
    public static List<MappingDto> getMappings() {
        List<MappingDto> results = new List<MappingDto>();
        for (TwinFieldMapConfig__c record : [
            SELECT Id, Name, SourceField__c, TargetField__c,
                   OverwriteRule__c, Transform__c, IsActive__c
            FROM TwinFieldMapConfig__c
            ORDER BY Name
        ]) {
            MappingDto dto = new MappingDto();
            dto.id = record.Id;
            dto.label = record.Name;
            dto.sourceField = record.SourceField__c;
            dto.targetField = record.TargetField__c;
            dto.overwriteRule = record.OverwriteRule__c;
            dto.transform = record.Transform__c;
            dto.isActive = record.IsActive__c;
            results.add(dto);
        }
        return results;
    }


    @AuraEnabled
    public static SaveResultDto saveMappings(
        List<MappingInput> mappings,
        List<Id> deletedIds
    ) {
        SaveResultDto result = new SaveResultDto();
        result.statusText = 'Success';

        try {
            Map<String, Schema.DisplayType> sourceTypes = getFieldTypeMap(QuoteLineItem.SObjectType);
            Map<String, Schema.DisplayType> targetTypes = getFieldTypeMap(OpportunityLineItem.SObjectType);

            List<TwinFieldMapConfig__c> toUpsert = new List<TwinFieldMapConfig__c>();
            if (mappings != null) {
                for (MappingInput input : mappings) {
                    validateInput(input, sourceTypes, targetTypes);

                    String label = String.isBlank(input.label)
                        ? input.sourceField + ' to ' + input.targetField
                        : input.label;

                    TwinFieldMapConfig__c record = new TwinFieldMapConfig__c(
                        Id = input.id,
                        Name = label,
                        SourceObject__c = SOURCE_OBJECT,
                        SourceField__c = input.sourceField,
                        TargetObject__c = TARGET_OBJECT,
                        TargetField__c = input.targetField,
                        OverwriteRule__c = input.overwriteRule,
                        Transform__c = normalizeTransform(input.transform),
                        IsActive__c = input.isActive == null ? true : input.isActive
                    );
                    toUpsert.add(record);
                }
            }

            if (!toUpsert.isEmpty()) {
                upsert toUpsert;
            }

            if (deletedIds != null && !deletedIds.isEmpty()) {
                delete [SELECT Id FROM TwinFieldMapConfig__c WHERE Id IN :deletedIds];
            }
        } catch (Exception ex) {
            String message = ex.getMessage();
            if (ex instanceof MappingValidationException) {
                message = ex.getMessage();
            } else if (message == null || message == 'Script-thrown exception') {
                message = 'Unexpected error while saving mappings.';
            }
            result.statusText = 'Failed: ' + message;
        }

        return result;
    }

    private static List<FieldOption> buildFieldOptions(Schema.SObjectType sObjectType, Boolean includeReadOnly) {
        Map<String, Schema.SObjectField> fields = sObjectType.getDescribe().fields.getMap();
        List<FieldOption> options = new List<FieldOption>();

        for (Schema.SObjectField field : fields.values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            Schema.DisplayType type = describe.getType();
            if (!SUPPORTED_TYPES.contains(type)) {
                continue;
            }
            if (!isCustomField(describe)) {
                continue;
            }

            if (includeReadOnly) {
                if (!describe.isAccessible() || describe.isCalculated()) {
                    continue;
                }
            } else {
                if (!describe.isUpdateable() || describe.isCalculated()) {
                    continue;
                }
            }

            FieldOption option = new FieldOption();
            option.label = describe.getLabel() + ' (' + String.valueOf(type) + ')';
            option.apiName = describe.getName();
            option.dataType = String.valueOf(type);
            options.add(option);
        }

        options.sort(new FieldOptionComparator());
        return options;
    }

    private static Map<String, Schema.DisplayType> getFieldTypeMap(Schema.SObjectType sObjectType) {
        Map<String, Schema.DisplayType> results = new Map<String, Schema.DisplayType>();
        for (Schema.SObjectField field : sObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (!isCustomField(describe)) {
                continue;
            }
            results.put(describe.getName(), describe.getType());
        }
        return results;
    }

    private static void validateInput(
        MappingInput input,
        Map<String, Schema.DisplayType> sourceTypes,
        Map<String, Schema.DisplayType> targetTypes
    ) {
        if (input == null) {
            throw new MappingValidationException('Mapping input is required.');
        }
        if (String.isBlank(input.sourceField) || String.isBlank(input.targetField)) {
            throw new MappingValidationException(
                'Source and target fields are required. ' +
                'Source="' + String.valueOf(input.sourceField) + '", ' +
                'Target="' + String.valueOf(input.targetField) + '".'
            );
        }
        if (String.isBlank(input.overwriteRule)) {
            throw new MappingValidationException('Overwrite rule is required.');
        }
        if (!sourceTypes.containsKey(input.sourceField) || !targetTypes.containsKey(input.targetField)) {
            throw new MappingValidationException('Invalid source or target field.');
        }

        Schema.DisplayType sourceType = sourceTypes.get(input.sourceField);
        Schema.DisplayType targetType = targetTypes.get(input.targetField);
        if (!SUPPORTED_TYPES.contains(sourceType) || !SUPPORTED_TYPES.contains(targetType)) {
            throw new MappingValidationException('Unsupported field type selected.');
        }
        if (!isCompatible(sourceType, targetType)) {
            throw new MappingValidationException('Source and target field types are not compatible.');
        }
    }

    private static Boolean isCompatible(Schema.DisplayType sourceType, Schema.DisplayType targetType) {
        return sourceType == targetType;
    }

    private static Boolean isNumericType(Schema.DisplayType type) {
        return type == Schema.DisplayType.Double
            || type == Schema.DisplayType.Currency
            || type == Schema.DisplayType.Integer
            || type == Schema.DisplayType.Percent;
    }

    private static String normalizeTransform(String transform) {
        return String.isBlank(transform) ? 'None' : transform;
    }


    private static Boolean isCustomField(Schema.DescribeFieldResult describe) {
        if (describe.getName() == null) {
            return false;
        }
        String nameValue = describe.getName();
        return nameValue.endsWith('__c')
            || nameValue.endsWith('__x')
            || nameValue.endsWith('__pc')
            || nameValue.endsWith('__s');
    }

    private class FieldOptionComparator implements System.Comparator<FieldOption> {
        public Integer compare(FieldOption leftOption, FieldOption rightOption) {
            if (leftOption == null && rightOption == null) {
                return 0;
            }
            if (leftOption == null) {
                return 1;
            }
            if (rightOption == null) {
                return -1;
            }
            String leftLabel = leftOption.label == null ? '' : leftOption.label.toLowerCase();
            String rightLabel = rightOption.label == null ? '' : rightOption.label.toLowerCase();
            return leftLabel.compareTo(rightLabel);
        }
    }
}
