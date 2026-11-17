@RestResource(urlMapping='/customer-webhook/v1')
global with sharing class CustomerWebhookAPI {

    global class CustomerData {
        public String customerName;
        public String phone;
    }

    global class APIResponse {
        public Boolean success;
        public String message;
        public String accountId;
    }

    @HttpPost
    global static APIResponse receiveData() {

        APIResponse response = new APIResponse();

        try {
            String jsonBody =
                RestContext.request.requestBody.toString();

            CustomerData data =
                (CustomerData) JSON.deserialize(
                    jsonBody,
                    CustomerData.class
                );

            if (data == null ||
                String.isBlank(data.customerName)) {
                RestContext.response.statusCode = 400;
                response.success = false;
                response.message = 'Customer Name is required';
                return response;
            }

            Account acc = new Account(
                Name = data.customerName,
                Phone = data.phone
            );

            insert as user acc;

            response.success = true;
            response.message = 'Account created successfully';
            response.accountId = acc.Id;

            RestContext.response.statusCode = 201;

        } catch (Exception ex) {
            RestContext.response.statusCode = 400;
            response.success = false;
            response.message = 'Unable to process request';
        }

        return response;
    }
}