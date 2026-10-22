/**
* @author: Hitarth Trivedi
* @dateModified: 2024-05-29
* @description: Mock Response Generator for CARFAXIntegration Class.
*/
@isTest
global class CARFAXMockHttpResponseGenerator implements HttpCalloutMock {

    global HTTPResponse respond(HTTPRequest req) {       
        System.assert(req.getEndpoint().contains('1HGCM66554A033052'), 'Endpoint is not correct.');
        System.assertEquals('GET', req.getMethod(),  'Request is not a GET.');
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{"example":"test"}');
        res.setStatusCode(200);
        return res;
    }
}