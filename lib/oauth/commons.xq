(:
 : Copyright 2010 28msec Inc.
 :)

(:~
 :
 : The OAuth Commons module acts as a wrapper for the OAuth (client) module.
 : This module simplifies the handling with OAuth event more because of its
 : predefined set of service providers.
 :
 : @see http://www.oauth.net
 :)
module namespace oac="http://www.28msec.com/templates/oauth/lib/oauth/commons";

import module namespace oauth="http://www.28msec.com/templates/oauth/lib/oauth/client";
import module namespace scs="http://www.28msec.com/modules/scs";
import module namespace http="http://www.28msec.com/modules/http";

import schema namespace oa="http://www.28msec.com/modules/oauth/client" at "schemas/client.xsd";

(: ##############################################
   #
   #   Service providers
   #
   ############################################## :)

(:~
 : Creates the config element for Doodle (www.doodle.com)
 :
 : @param $consumer-key The consumer key from the service provider
 : @param $consumer-key-secret The consumer key secret from the service provider
 : @param $callback-url The callback URL that the service provider should use
 : @param $doodle-get Doodle specific parameter
 : @return The Doodle config element
 :)
declare function oac:config-doodle( $consumer-key as xs:string, 
                                    $consumer-key-secret as xs:string, 
                                    $callback-url as xs:string, 
                                    $doodle-get as xs:string
                                  ) as schema-element (oa:config)
{
  validate {
  <oa:config>
  {
    oac:service-provider ("doodle.com/api1",
                          "http://doodle.com/api1/oauth/requesttoken", "GET",
                          "https://doodle.com/mydoodle/consumer/authorize.html",
                          "http://doodle.com/api1/oauth/accesstoken", "GET",
                          $consumer-key, $consumer-key-secret)
  }
    <oa:callback-url>{ $callback-url }</oa:callback-url>
    <oa:request-token>  
      <oa:parameters>
        <oa:parameter name="doodle_get">{ $doodle-get }</oa:parameter>
      </oa:parameters>
    </oa:request-token>
    <oa:user-authorization>
      <oa:parameters>
        <oa:parameter name="oauth_callback">{ $callback-url }</oa:parameter>
      </oa:parameters>
    </oa:user-authorization>
  </oa:config> }
};

(:~
 : Creates the config element for Google (www.google.com)
 :
 : @param $consumer-key The consumer key from the service provider
 : @param $consumer-key-secret The consumer key secret from the service provider
 : @param $callback-url The callback URL that the service provider should use
 : @param $scope Google specific parameter
 : @return The Google config element
 :)
declare function oac:config-google( $consumer-key as xs:string, 
                                    $consumer-key-secret as xs:string, 
                                    $callback-url as xs:string, 
                                    $scope as xs:string
                                  ) as schema-element (oa:config)
{
  validate {
  <oa:config>
  {
    oac:service-provider ("www.google.com",
                          "https://www.google.com/accounts/OAuthGetRequestToken", "POST",
                          "https://www.google.com/accounts/OAuthAuthorizeToken",
                          "https://www.google.com/accounts/OAuthGetAccessToken", "POST",
                          $consumer-key, $consumer-key-secret)
  }
    <oa:callback-url>{ $callback-url }</oa:callback-url>
    <oa:request-token>  
      <oa:parameters>
        <oa:parameter name="scope">{ $scope }</oa:parameter>
      </oa:parameters>
    </oa:request-token>
  </oa:config> }
};

(:~
 : Creates the config element for Twitter (www.twitter.com)
 :
 : @param $consumer-key The consumer key from the service provider
 : @param $consumer-key-secret The consumer key secret from the service provider
 : @param $callback-url The callback URL that the service provider should use
 : @return The Twitter config element
 :)
declare function oac:config-twitter( $consumer-key as xs:string, 
                                     $consumer-key-secret as xs:string, 
                                     $callback-url as xs:string
                                   ) as schema-element (oa:config)
{
  validate {
  <oa:config>
  {
    oac:service-provider ("twitter.com",
                          "http://twitter.com/oauth/request_token", "GET",
                          "http://twitter.com/oauth/authorize",
                          "http://twitter.com/oauth/access_token", "POST",
                          $consumer-key, $consumer-key-secret)
  }
    <oa:callback-url>{ $callback-url }</oa:callback-url>
  </oa:config> }
};

(:~
 : Creates the config element for Sausalito OAuth Server Template (running on localhost:8081)
 :
 : @param $consumer-key The consumer key from the service provider
 : @param $consumer-key-secret The consumer key secret from the service provider
 : @param $callback-url The callback URL that the service provider should use
 : @param $own-parameter Application specific parameter
 : @param $address The address of the oauth server (e.g. 'http://oauth.28msec.com:8080'). If empty sequence is passed, 'http://127.0.0.1:8081' is used.
 : @return The Localhost config element
 :)
declare function oac:config-localhost( $consumer-key as xs:string, 
                                       $consumer-key-secret as xs:string, 
                                       $callback-url as xs:string,
                                       $own-parameter as xs:string,
                                       $address as xs:string?
                                     ) as schema-element (oa:config)
{
  validate {
  <oa:config>
  {
    let $def_address := if ($address) then $address else "http://127.0.0.1:8081/"
    return
      oac:service-provider ("localhost",
                            fn:concat($def_address,"oauth/request-token"), "GET",
                            fn:concat($def_address,"oauth/authorization"),
                            fn:concat($def_address,"oauth/access-token"), "GET",
                            $consumer-key, $consumer-key-secret)
  }
    <oa:callback-url>{ $callback-url }</oa:callback-url>
    <oa:request-token>  
      <oa:parameters>
        <oa:parameter name="own_parameter">{ $own-parameter }</oa:parameter>
      </oa:parameters>
    </oa:request-token>
  </oa:config> }
};


(:~
 : Creates the config element for Dropbox (www.dropbox.com)
 :
 : @param $consumer-key The consumer key from the service provider
 : @param $consumer-key-secret The consumer key secret from the service provider
 : @param $callback-url The callback URL that the service provider should use
 : @return The Dropbox config element
 :)
declare function oac:config-dropbox( $consumer-key as xs:string, 
                                    $consumer-key-secret as xs:string, 
                                    $callback-url as xs:string)
                                    as schema-element (oa:config)
{
  validate {
  <oa:config>
  {
    oac:service-provider ("https://api.dropbox.com/1",
                          "https://api.dropbox.com/1/oauth/request_token", "POST",
                          "https://www.dropbox.com/1/oauth/authorize",
                          "https://api.dropbox.com/1/oauth/access_token", "POST",
                          $consumer-key, $consumer-key-secret)
  }
    <oa:callback-url>{ $callback-url }</oa:callback-url>
    <oa:user-authorization>
      <oa:parameters>
        <oa:parameter name="oauth_callback">{ $callback-url }</oa:parameter>
      </oa:parameters>
    </oa:user-authorization>
  </oa:config> }
};


(: ##############################################
   #
   #   Other public functions
   #
   ############################################## :)

(:~
 : Gets the request token and executes http redirect 
 : to service provider (step 1 and 2 of OAuth workflow)
 :
 : @param $config The service provider specific config element
 : @return The empty sequence (does a redirect to the service providers authorization URL)
 : @error OAuth specific errors (@see oauth:request-token)
 :)
declare sequential function oac:init($config as schema-element (oa:config)) as empty-sequence()
{
  (: get parameters from the config for the request token :)
  let $service-provider := $config/oa:service-provider
  let $callback-url := $config/oa:callback-url/text()
  let $parameters := $config/oa:request-token/oa:parameters
  let $headers := $config/oa:request-token/oa:headers
  
  (: ask the service provider for a request token pair (token / token secret) :)
  let $request-token-pair := oauth:request-token($service-provider, $callback-url, $parameters, $headers)
  
  (: get parameters from the config for the user authorization :)
  let $authorization-parameters := $config/oa:user-authorization/oa:parameters
  
  return 
  (
    (: save the request-token-pair in the cookie :)   
    scs:set(<token type="request">{ $request-token-pair }</token>),
      
    (: let the user be redirected to the authorization url (so that he can authorize the request token :)
    oauth:user-authorization($service-provider, $request-token-pair, $authorization-parameters)
  )
};

(:~
 : Has to be called as first function after callback from service provider.
 : This function gets the access token and stores it in the cookie.
 :
 : @param $config The service provider specific config element
 : @return The empty sequence
 : @error Saved and received token do not match
 : @error No cookie containing the request token was found
 : @error OAuth specific errors (@see oauth:access-token)
 :)
declare sequential function oac:callback($config as schema-element (oa:config)) as empty-sequence()
{
  (: extract the OAuth verifier parameter :)
  let $oauth-verifier := http:get-parameters("oauth_verifier")[1]
  let $oauth-token := http:get-parameters("oauth_token")[1]
  
  (: get the config (service-provider & request token pair) from the cookie :)
  let $service-provider := $config/oa:service-provider
  let $cookie := scs:get()
  let $type := fn:data(scs:get()/@type)
  return
    if ($type = "access") then (: is there an access-token in the cookie :)
      () (: then do nothing :)
    else
      if ($type = "request") then (: is there a request-token in the cookie :)
      (
        let $request-token-pair := validate { $cookie/node() }
  
        (: check if received token and saved token are equal :)
        return
          if (fn:empty($oauth-token) or ($oauth-token eq $request-token-pair/oa:token/text())) then
          (
            (: exchange the data for an access token :)
            let $access-token-pair := oauth:access-token($service-provider, $request-token-pair, $oauth-verifier)

            (: save access token & access token secret for further use :)
            return scs:set (<token type="access">{ $access-token-pair }</token>)
          )
          else
            fn:error(xs:QName('OAUTH_COMMONS_CALLBACK_NO_TOKEN_MATCH'), "Save and received token values do not match.", $request-token-pair)          
      )
      else
        fn:error(xs:QName('OAUTH_COMMONS_CALLBACK_NO_REQUEST_TOKEN_SET'), "No cookie containing the request token was found", ())
};


(:~
 : Retrieves the protected resource
 :
 : @param $config The service provider specific config element
 : @param $http-request A http request structure specifying which and how to access the resource
 : @return A http response structure containg the response for the issued request
 : @error No cookie containing the access token was found
 : @error OAuth specific errors (@see oauth:protected-resource)
 :)
declare sequential function oac:resource( $config as schema-element (oa:config),
                               $http-request as schema-element (oa:http-request)
                             ) as schema-element (oa:http-response)
{
  (: get the access token pair from the cookie :)
  let $service-provider := $config/oa:service-provider
  let $type := fn:data(scs:get()/@type)
  return
    if ($type = "access") then
      let $access-token-pair := validate { scs:get()/node() }
      return oauth:protected-resource($service-provider, $http-request, $access-token-pair)
    else
      fn:error(xs:QName('OAUTH_COMMONS_RESOURCE_NO_ACCESS_TOKEN_SET'), "No cookie containing the access token was found", ())
};

(: ##############################################
   #
   #   Internal Helper Functions
   #
   ############################################## :)

(:~
 : Generates a default service provider structure (OAuth Version 1.0, HMAC-SHA1)
 :
 : @param $realm Realm of the service provider
 : @param $request-token-url The URL used for acquiring the request token 
 : @param $request-token-http-method The http method to use for the request token request
 : @param $user-authorization-url The URL where to redirect the consumer to
 : @param $access-token-url The URL used for exchanging the request token through an access token
 : @param $access-token-http-method The http method to use for the access token request
 : @param $consumer-key The consumer key from the service provider
 : @param $consumer-key-secret The consumer key secret from the service provider
 : @return The service provider structure
 :)
declare function oac:service-provider ($realm as xs:string,
                                       $request-token-url as xs:string,
                                       $request-token-http-method as xs:string,
                                       $user-authorization-url as xs:string,
                                       $access-token-url as xs:string,
                                       $access-token-http-method as xs:string,
                                       $consumer-key as xs:string,
                                       $consumer-key-secret as xs:string) as schema-element (oa:service-provider)
{
  validate {
  <oa:service-provider realm="{ $realm }"> 
    <oa:request-token>
      <oa:url>{ $request-token-url }</oa:url>
      <oa:http-method>{ $request-token-http-method }</oa:http-method>
    </oa:request-token>
    <oa:user-authorization>
      <oa:url>{ $user-authorization-url }</oa:url>
    </oa:user-authorization>
    <oa:access-token>
      <oa:url>{ $access-token-url }</oa:url>
      <oa:http-method>{ $access-token-http-method }</oa:http-method>
    </oa:access-token>
    <oa:supported-signature-methods>
      <oa:method>HMAC-SHA1</oa:method>
    </oa:supported-signature-methods>  
    <oa:oauth-version>1.0</oa:oauth-version>
    <oa:authentication>
      <oa:consumer-key>{ $consumer-key }</oa:consumer-key>
      <oa:consumer-key-secret>{ $consumer-key-secret }</oa:consumer-key-secret>
    </oa:authentication>
  </oa:service-provider> }
};
