public with sharing class TwinFieldFlowReconcileInvocable {
    public class Request {
        @InvocableVariable public String mappingsJson;
        @InvocableVariable public String deletedIdsJson;
    }

    public class Response {
        @InvocableVariable public String statusText;
        @InvocableVariable public String errorText;
    }

    @InvocableMethod(label='Reconcile Mapping Rows')
    public static List<Response> reconcile(List<Request> requests) {
        Response response = new Response();
        response.statusText = 'Success';
        response.errorText = null;

        try {
            if (requests == null || requests.isEmpty()) {
                response.statusText = 'Failed';
                response.errorText = 'No input provided.';
                return new List<Response>{ response };
            }

            Request request = requests[0];
            List<TwinFieldMappingController.MappingInput> mappings =
                parseMappings(request.mappingsJson);
            List<Id> deletedIds = parseDeletedIds(request.deletedIdsJson);

            TwinFieldMappingController.SaveResultDto result =
                TwinFieldMappingController.saveMappings(mappings, deletedIds);
            if (result == null) {
                response.statusText = 'Failed';
                response.errorText = 'No result.';
            } else if (result.statusText != null && result.statusText.startsWith('Failed:')) {
                response.statusText = 'Failed';
                response.errorText = result.statusText.replace('Failed:', '').trim();
            } else {
                response.statusText = result.statusText;
                response.errorText = null;
            }
        } catch (Exception ex) {
            response.statusText = 'Failed';
            response.errorText = ex.getMessage();
        }

        return new List<Response>{ response };
    }

    private static List<TwinFieldMappingController.MappingInput> parseMappings(String jsonValue) {
        if (String.isBlank(jsonValue)) {
            return new List<TwinFieldMappingController.MappingInput>();
        }
        return (List<TwinFieldMappingController.MappingInput>)JSON.deserialize(
            jsonValue,
            List<TwinFieldMappingController.MappingInput>.class
        );
    }

    private static List<Id> parseDeletedIds(String jsonValue) {
        if (String.isBlank(jsonValue)) {
            return new List<Id>();
        }
        return (List<Id>)JSON.deserialize(jsonValue, List<Id>.class);
    }
}
