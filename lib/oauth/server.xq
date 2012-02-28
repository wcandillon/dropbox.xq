(:
 : Copyright 2010 28msec Inc.
 :)

(:~
 :
 : The OAuth Server module allows you to play the role of a service provider in an OAuth process.
 :
 : @see http://www.oauth.net
 :)
module namespace oauth-server = "http://www.28msec.com/modules/oauth/server";

(: Module Imports :)
import module namespace http ="http://www.28msec.com/modules/http";
import module namespace random ="http://www.28msec.com/modules/random";
import module namespace oauth ="http://www.28msec.com/modules/oauth/client";
import module namespace functx ="http://www.functx.com";
import module namespace xqddf = "http://www.zorba-xquery.com/modules/xqddf";
import module namespace utils="http://www.28msec.com/modules/utils";

(: Schema Imports :)
import schema namespace oas="http://www.28msec.com/modules/oauth/server";
import schema namespace oa="http://www.28msec.com/modules/oauth/client";

(: Collection Declarations :)
declare ordered collection oauth-server:consumers as node()*;
declare ordered collection oauth-server:tokens as node()*;

(: TODO: use synchronized collections instead of the normal ones :)
declare variable $oauth-server:consumers       := xs:QName("oauth-server:consumers");
declare variable $oauth-server:tokens          := xs:QName("oauth-server:tokens");

(: Length of random values (token / verifier) :)
declare variable $oauth-server:random-length   := xs:unsignedInt(30);
declare variable $oauth-server:verifier-length := xs:unsignedInt(10);

(: Token Lifetime :)
declare variable $oauth-server:request-token-lifetime := xs:duration("PT5M"); (: 5 Minutes for request and authorized request tokens :)


(: ##############################################
   #
   #   Request handler functions 
   #
   ############################################## :)
   
(:~
 :
 : If a consumer calls this function, he has to identifier himself, that might be an email 
 : addresse or the username he used to register within the service provider. 
 : The oauth-server module then needs to generate a new consumer-key and a consumer-secret-key 
 : and stores that information for furture verification.
 : It might be possible to register more than one consumer key per identifier.
 :
 : @param $identifier The identifier of the consumer
 : @return The token containing the consumer-key and the consumer-secret (and the identifier)
 :)
declare sequential function oauth-server:register ($identifier as xs:string) as schema-element (oas:token)
{
  let $consumer-key := random:random-string($oauth-server:random-length)
  return
    if (fn:empty(xqddf:collection($oauth-server:consumers)[oas:consumer-key eq $consumer-key])) then
      let $consumer-secret := random:random-string($oauth-server:random-length)
      let $consumer :=
        validate {
          <oas:token timestamp="{ fn:current-dateTime() }" status="consumer">
            <oas:identifier>{ $identifier }</oas:identifier>
            <oas:consumer-key>{ $consumer-key }</oas:consumer-key>
            <oas:consumer-secret>{ $consumer-secret }</oas:consumer-secret>
          </oas:token>
        }
      return 
        block {
          xqddf:insert-nodes-last($oauth-server:consumers, $consumer);
          $consumer;
        }
    else (: this consumer key is already used --> try again :)
      oauth-server:register($identifier)
};

(:~
 :
 : To remove a consumer pair, the service provider needs to provide an interface to.
 : Because an identifier may have more than one consumer key, he needs to have the 
 : possiblity to remove only one.
 :
 : @param $identifier The identifier of the consumer
 : @param $consumer-key The comsumer-key of the consumer
 : @return true if the identifier consumer-key pair is valid (and was now removed successfully)
 :)
declare sequential function oauth-server:unregister ($identifier as xs:string, $consumer-key as xs:string) as xs:boolean
{
  let $consumer := xqddf:collection($oauth-server:consumers)[oas:identifier eq $identifier and oas:consumer-key eq $consumer-key]
  let $tokens := xqddf:collection($oauth-server:tokens)[oas:identifier eq $identifier and oas:consumer-key eq $consumer-key]
  return
    if (fn:empty($consumer)) then
      fn:false()
    else
      block {
        xqddf:delete-nodes($oauth-server:consumers, $consumer);
        if (fn:empty($tokens)) then
          ()
        else
          xqddf:delete-nodes($oauth-server:tokens, $tokens);
        fn:true();
      }
};

(: ##############################################
   #
   #   OAuth process functions
   #
   ############################################## :)

(:~
 :
 : Beside the required parameters the user may submit additional parameters. 
 : This additional parameters have to be handled by the application itself, not by the oauth-server module.
 : This function gets all the oauth parameter, may they be in the Authorization Header 
 : or as get parameter or in the post body. This parameters are verified (consumer-key, signature verification, 
 : timestamp, nonce, ...) and if everything is okay, the module will produce a new token pair. 
 : According to Spec 1.0a, it also returns an element saying that the given callback url was accepted (this 
 : means that in the next step, the user authorization, this callback url have to be used).
 :
 : @param $provider-specific-parameters The parameters from the service provider that have to be returned with the request token response
 : @return HTTP response that is sent to the consumer containing the request token and the provider specific parameters
 :)
declare sequential function oauth-server:request-token($provider-specific-parameters as schema-element (oa:parameters)?,
                                                       $request-url as xs:string)
{
  try {
    let $verification := oauth-server:verify-request($oauth-server:consumers, 
                                                     oas:request-status("request token"), 
                                                     $request-url)
    let $verification-token := $verification[1]
    let $verification-parameters := $verification[2]
    let $fresh-token := oauth-server:fresh-token()
    let $token :=
      validate {
        <oas:token timestamp="{ fn:current-dateTime() }" status="request">
        {
          $verification-token/oas:identifier,
          $verification-token/oas:consumer-key,
          $verification-token/oas:consumer-secret,
          (
            if (fn:string-length($verification-parameters/oa:parameter[@name eq "oauth_callback"]) eq 0) then
              fn:error(xs:QName("OAUTH_SERVER_REQUEST_TOKEN_NO_CALLBACK"), "Missing parameter (Callback URL)", $verification-parameters)
            else
              <oas:callback-url>{ $verification-parameters/oa:parameter[@name eq "oauth_callback"]/text() }</oas:callback-url>
          ),
          $fresh-token/oas:token-key,
          $fresh-token/oas:token-secret
        }
        </oas:token>
      }
    return
      block {
        xqddf:insert-nodes-last($oauth-server:tokens, $token);
        oauth-server:prepare-token-response($token, $provider-specific-parameters);
      }
  }
  catch * ($code, $desc, $obj) 
  {
    oauth-server:handle-error($code, $desc, $obj)
  }
};


(:~
 :
 : Returns information (callback-url, consumer-key) about the application requesting authorization
 :
 : @param $oauth-token The oauth token (request token) from the consumer
 : @return Authorization information about the application to which the given token was issued
 :)
declare sequential function oauth-server:user-authorization-information($oauth-token as xs:string) as schema-element (oas:authorization-information)
{
  let $token := oauth-server:verify-user-authorization-request($oauth-token)
  return
    validate {
      <oas:authorization-information>
        { $token/oas:consumer-key }
        { $token/oas:callback-url }
      </oas:authorization-information>
    }
};

(:~
 :
 : 1. Check if request-token is valid
 : 2. Insert authorized identifier and verifier into token
 : 3. Redirect user to consumer with token and verifier
 :
 : @param $oauth-token The oauth token (request token) from the consumer
 : @param $identifier The identifier of the consumer (that was retrieved when he logged in to your application)
 : @return Empty sequence (the consumer will be redirected to the callback URL specified earlier on)
 :)
declare sequential function oauth-server:user-authorization($oauth-token as xs:string, $identifier as xs:string) as empty-sequence()
{
  try 
  {
    let $verification-token := oauth-server:verify-user-authorization-request($oauth-token)
    let $verifier := random:random-string($oauth-server:verifier-length)
    let $authorized-identifier-element := <oas:authorized-identifier>{ $identifier }</oas:authorized-identifier>
    let $verifier-element := <oas:verifier>{ $verifier }</oas:verifier>
    let $callback-url := $verification-token/oas:callback-url/text()
    let $url-parameters := fn:concat("oauth_token=", $verification-token/oas:token-key/text(), "&amp;", "oauth_verifier=", $verifier)
    let $url := 
      if (fn:contains($callback-url, "?")) then
        fn:string-join( ($callback-url, $url-parameters), "&amp;" )
      else
        fn:string-join( ($callback-url, $url-parameters), "?" )
    return
      block {
        insert node $authorized-identifier-element as last into $verification-token;
        insert node $verifier-element as last into $verification-token;
        replace value of node $verification-token/@status with oas:token-status("authorized-request");
        replace value of node $verification-token/@timestamp with fn:current-dateTime();
        delete node $verification-token/oas:callback-url;
        http:set-redirect($url);
    }
  }
  catch * ($code, $desc, $obj) 
  {
    oauth-server:handle-error($code, $desc, $obj)
  }
};

(:~
 :
 : Request for an access token.
 : No additional parameters are allowed to be send with this request. But the service provider may return parameters
 :
 : @param $provider-specific-parameters The parameters from the service provider that have to be returned with the access token response
 : @param $accept-2-legged-oauth Has to be true if the application should allow to exchange an request token without authorization through an acces token
 : @return HTTP response that is sent to the consumer containing the access token and the provider specific parameters
 :)
declare sequential function oauth-server:access-token($provider-specific-parameters as schema-element (oa:parameters)?, 
                                                      $accept-2-legged-oauth as xs:boolean,
                                                      $request-url as xs:string)
{
  try
  {
    let $current-request-for :=
      if ($accept-2-legged-oauth) then
        oas:request-status("access token (2-legged)")
      else
        oas:request-status("access token (3-legged)")
    let $verification := oauth-server:verify-request($oauth-server:tokens, $current-request-for, $request-url)
    let $verification-token := $verification[1]
    let $fresh-token := oauth-server:fresh-token()
    return
      block {
        replace value of node $verification-token/oas:token-key with $fresh-token/oas:token-key;
        replace value of node $verification-token/oas:token-secret with $fresh-token/oas:token-secret;
        replace value of node $verification-token/@status with oas:token-status("access");
        replace value of node $verification-token/@timestamp with fn:current-dateTime();
        delete node $verification-token/oas:verifier;
        oauth-server:prepare-token-response(validate { $verification-token }, $provider-specific-parameters);
      }
  }
  catch * ($code, $desc, $obj) 
  {
    oauth-server:handle-error($code, $desc, $obj)
  }
};

(:~
 :
 : Verifies the request parameters and returns the saved token (including authorized-identifier)
 :
 : @return Access token issued for this consumer
 : @error @see oauth-server:verify-request
 :)
declare sequential function oauth-server:verify-resource-access($request-url as xs:string) as schema-element (oas:token)
{
  let $verification := oauth-server:verify-request($oauth-server:tokens, oas:request-status("protected resource"), $request-url)
  return validate { $verification[1] } (: return the token, so the service provider can do access control to its resources :)
};

(: ##############################################
   #
   #   Administrative functions
   #
   ############################################## :)

(:~
 :
 : Removes all access tokens older than the specified duration
 :
 : @param $older-than Duration specifying the the range of access tokens to remove / revoke
 :)
declare sequential function oauth-server:remove-access-tokens-older-than($older-than as xs:duration) as empty-sequence()
{
  let $timestamp := fn:current-dateTime() - $older-than
  let $token-status := oas:token-status("access")
  let $tokens := xqddf:collection($oauth-server:tokens)[@status eq $token-status and xs:dateTime(@timestamp) lt $timestamp]
  return 
    if (fn:empty($tokens)) then
      ()
    else  
      block {
        xqddf:delete-nodes( $oauth-server:tokens, $tokens);
        ();
      }
};

(: ##############################################
   #
   #   Error handling
   #
   ############################################## :)

(:~
 :
 : Handles the fn:error by "throwing" an HTTP error code instead
 :
 : @param $code Error code
 : @param $esc Description of the error
 : @param $obj Object assigned with the error
 : @return HTTP error response (HTTP Code 400 / 401)
 :)
declare sequential function oauth-server:handle-error($code as xs:QName, $desc as xs:string, $obj)
{
(:
    *  HTTP 400 Bad Request
          o Unsupported parameter
          o Unsupported signature method
          o Missing required parameter
          o Duplicated OAuth Protocol Parameter
    * HTTP 401 Unauthorized
          o Invalid Consumer Key
          o Invalid / expired Token
          o Invalid signature
          o Invalid / used nonce
:)
  let $bad-request-400 :=
  (
    xs:QName("OAUTH_SERVER_REQUEST_TOKEN_NO_CALLBACK"),
    xs:QName("OAUTH_SERVER_SIGNATURE_METHOD_MISSING"),
    xs:QName("OAUTH_SERVER_PARAMETERS_MISSING_TOKEN"),
    xs:QName("OAUTH_SERVER_MISSING_PARAMETERS")
    
  )
  let $unauthorized-401 :=
  (
    xs:QName("OAUTH_SERVER_PARAMETER_VERIFICATION_INVALID_TOKEN"),
    xs:QName("OAUTH_SERVER_USER_AUTHORIZATION_INVALID_TOKEN"),
    xs:QName("OAUTH_SERVER_INVALID_SIGNATURE"),
    xs:QName("OAUTH_SERVER_TIMESTAMP_NONCE_NO_ENTRY"),
    xs:QName("OAUTH_SERVER_TIMESTAMP_NONCE_TIMESTAMP_TOO_OLD"),
    xs:QName("OAUTH_SERVER_TIMESTAMP_NONCE_NONCE_ALREADY_USED")
  )
  return
    if ($code = $unauthorized-401) then
      oauth-server:http-error(401, $desc)
    else
      oauth-server:http-error(400, $desc)
};

(: ##############################################
   #
   #   Internal functions
   #
   ############################################## :)

(: sends an http error with the given description :)
declare sequential function oauth-server:http-error($http-code as xs:integer, $description as xs:string)
{
  http:set-status($http-code),
  http:set-content-type("text/plain"),
  $description
};

(: used to prepare the response for request token and access token :)
declare sequential function oauth-server:prepare-token-response( $token as schema-element (oas:token), 
                                                      $provider-specific-parameters as schema-element (oa:parameters)?
                                                    )
{
  let $parameters :=
    <oa:parameters>
      <oa:parameter name="oauth_token">{ $token/oas:token-key/text() }</oa:parameter>
      <oa:parameter name="oauth_token_secret">{ $token/oas:token-secret/text() }</oa:parameter>
      {
        if (fn:string-length($token/oas:callback-url/text()) eq 0) then
          ()
        else
          <oa:parameter name="oauth_callback_confirmed">TRUE</oa:parameter>
      }
      { $provider-specific-parameters/oa:parameter }
    </oa:parameters>
  return
  (
    http:set-content-type("text/plain"),
    oauth-server:parameters-in-url-form(validate { $parameters })
  )
};

declare function oauth-server:parameters-in-url-form($parameters as schema-element (oa:parameters)?) as xs:string
{
  fn:string-join(oauth:parameters-in-url-form($parameters), "&amp;")
};

(: remove old tokens (request and authorized-request tokens) :)
declare sequential function oauth-server:remove-tokens() as empty-sequence()
{
  let $timestamp := fn:current-dateTime() - $oauth-server:request-token-lifetime
  let $token-status := (oas:token-status("request"), oas:token-status("authorized-request"))
  let $tokens := xqddf:collection($oauth-server:tokens)[@status = $token-status and xs:dateTime(@timestamp) lt $timestamp]
  return
    if (fn:empty($tokens)) then
      ()
    else
      block {
        xqddf:delete-nodes( $oauth-server:tokens, $tokens);
        ();
      }
};

(:
  Verify the OAuth parameters and returns ($token, $parameters) if everything is okay, error otherwise
  Us used for verifying the OAuth parameters for the request token, access token and protected resource
  (not for user authorization)
:)
declare sequential function oauth-server:verify-request($token-origin as xs:QName, 
                                                        $current-request-for as oas:request-status,
                                                        $request-url as xs:string)
{
  oauth-server:remove-tokens();
  let $parameters := oauth-server:parameters($current-request-for)
  let $acceptable-token-status := oauth-server:acceptable-token-status-for-request($current-request-for)
  let $consumer-key := $parameters/oa:parameter[@name eq "oauth_consumer_key"]/text()
  let $token-key := $parameters/oa:parameter[@name eq "oauth_token"]/text()
  let $verifier := $parameters/oa:parameter[@name eq "oauth_verifier"]/text()
  let $token := xqddf:collection($token-origin)[@status = $acceptable-token-status 
                        and (fn:empty($consumer-key) or (oas:consumer-key eq $consumer-key))
                        and (fn:empty($token-key) or (oas:token-key eq $token-key))
                        and (fn:empty(oas:verifier) or (oas:verifier eq $verifier))]
  return
    if (fn:empty($token)) then
      fn:error(xs:QName("OAUTH_SERVER_PARAMETER_VERIFICATION_INVALID_TOKEN"), fn:concat("Invalid token (", $current-request-for, ")"), $parameters)
    else
      let $verification := ( $token, $parameters )
      return
      (
        oauth-server:verify-oauth-parameters (validate {$token}, $parameters, $request-url), (: TODO: token should already be validate before inserted into collection :)
        $verification
      );
};

declare sequential function oauth-server:verify-user-authorization-request($token-key as xs:string) as schema-element (oas:token)
{
  oauth-server:remove-tokens();
  let $token := xqddf:collection($oauth-server:tokens)[@status = oas:token-status("request") and (oas:token-key eq $token-key)]
  return
    if (fn:empty($token)) then
      fn:error(xs:QName("OAUTH_SERVER_USER_AUTHORIZATION_INVALID_TOKEN"), "Invalid token (user authorization)", ())
    else
      $token;
};

declare function oauth-server:acceptable-token-status-for-request($current-request-for as oas:request-status) as oas:token-status
{
  if ($current-request-for eq oas:request-status("request token")) then
    oas:token-status("consumer")
  else if ($current-request-for eq oas:request-status("access token (3-legged)")) then
    oas:token-status("authorized-request")
  else if ($current-request-for eq oas:request-status("access token (2-legged)")) then
    (oas:token-status("authorized-request"), oas:token-status("request"))
  else (: request for protected resource :)
    oas:token-status("access")
};


declare sequential function oauth-server:verify-oauth-parameters( $token as schema-element(oas:token), 
                                                       $parameters as schema-element (oa:parameters),
                                                       $request-url as xs:string
                                                     ) as empty-sequence()
{
  let $signature := $parameters/oa:parameter[@name eq "oauth_signature"]/text()
  let $signature-method := $parameters/oa:parameter[@name eq "oauth_signature_method"]/text()
  let $http-method := http:get-method()
  let $filtered-parameters := <oa:parameters>{ $parameters/oa:parameter[fn:not(@name eq "oauth_signature")] }</oa:parameters>
  let $base-string := oauth:base-string($http-method, $request-url, validate { $filtered-parameters })  
  let $consumer-secret := $token/oas:consumer-secret/text()
  let $token-secret := $token/oas:token-secret/text()
  (: 
    TODO / ISSUE: $key := fn:concat(...) works as long as only signature methods PLAINTEXT and HMAC-SHA1 are supported.
    Otherwise, like for example in case of RSA, the key is the private RSA key.
  :)
  let $key := fn:concat(fn:encode-for-uri($consumer-secret), "&amp;", fn:encode-for-uri($token-secret))
  let $computed-signature := oauth:signature($base-string, $signature-method, $key)
  let $result :=
    if ($computed-signature ne $signature) then
      fn:error(xs:QName("OAUTH_SERVER_INVALID_SIGNATURE"), "Signature is invalid", $signature)
    else
      (: returns empty if valid, fn:error otherwise :)
      oauth-server:verify-timestamp-nonce($parameters)
  return
    $result
};

(: verifies the timestamp and nonce combination :)
declare sequential function oauth-server:verify-timestamp-nonce($parameters as schema-element (oa:parameters)) as empty-sequence()  
{
  let $consumer-key := $parameters/oa:parameter[@name eq "oauth_consumer_key"]/text()
  let $timestamp :=  xs:positiveInteger($parameters/oa:parameter[@name eq "oauth_timestamp"]/text())
  let $nonce :=  $parameters/oa:parameter[@name eq "oauth_nonce"]/text()
  let $consumer-entry := xqddf:collection($oauth-server:consumers)[oas:consumer-key eq $consumer-key]
  return
    if (fn:empty($consumer-entry)) then
      fn:error(xs:QName("OAUTH_SERVER_TIMESTAMP_NONCE_NO_ENTRY"), "Consumer Entry not found (probably consumer unregistered in the meantime)", ())
    else
      let $last-timestamp := $consumer-entry/oas:last-timestamp
      let $new-timestamp-entry := 
        <oas:last-timestamp value="{ $timestamp }">
          <oas:nonce>{ $nonce }</oas:nonce>
        </oas:last-timestamp>
      return
        block {
          (
            if (fn:empty($last-timestamp)) then
              insert node $new-timestamp-entry as last into $consumer-entry
            else
              let $timestamp-value := xs:positiveInteger(fn:data($last-timestamp/@value))
              let $nonces := $last-timestamp/oas:nonce/text()
              return
                if ($timestamp lt $timestamp-value) then
                  fn:error(xs:QName("OAUTH_SERVER_TIMESTAMP_NONCE_TIMESTAMP_TOO_OLD"), "Used timestamp is too old", ())
                else if ($timestamp eq $timestamp-value) then
                  if ($nonce = $nonces) then (: was this nonce already used :)
                    fn:error(xs:QName("OAUTH_SERVER_TIMESTAMP_NONCE_NONCE_ALREADY_USED"), "Nonce already used before", ())
                  else
                    insert node <oas:nonce>{ $nonce }</oas:nonce> as last into $last-timestamp
                else (: timestamp is newer, therefore everything is okay :)
                  replace node $last-timestamp with $new-timestamp-entry
          );
          ();
        }
};

(: gets all parameters (from get, body, authorization header [excluding realm]) :)
declare function oauth-server:parameters($current-request-for as xs:string) as schema-element (oa:parameters)
{
  let $parameters := oauth-server:receive-parameters()
  return (: verify parameter occurence :)
  (
    oauth-server:check-parameter-availability($parameters),
    
    (: token-key is only allowed to be missing if request token request:)
    if (fn:not($current-request-for = "request token") and fn:empty($parameters/oa:parameter[@name eq "oauth_token"])) then
      fn:error(xs:QName("OAUTH_SERVER_MISSING_PARAMETERS"), "Missing parameter (oauth_token)", $parameters)
    
    (: verifier has to be given if its a request for an access token :)
    else if ($current-request-for = "access token" and fn:empty($parameters/oa:parameter[@name eq "oauth_verifier"])) then
      fn:error(xs:QName("OAUTH_SERVER_MISSING_PARAMETERS"), "Missing parameter (oauth_verifier)", $parameters)
      
    else (: all required OAuth parameters are given :)
      $parameters
  )
};

declare function oauth-server:check-parameter-availability($parameters as schema-element(oa:parameters)) as empty-sequence()
{
  for $parameter-name in (
                "oauth_consumer_key",
                "oauth_signature_method",
                "oauth_signature",
                "oauth_timestamp",
                "oauth_nonce"
              )
  return
    if (fn:empty($parameters/oa:parameter[@name eq $parameter-name])) then
      fn:error(xs:QName("OAUTH_SERVER_MISSING_PARAMETERS"), fn:concat("Missing parameter (", $parameter-name ,")"), $parameters)
    else
      ()
};

declare function oauth-server:receive-parameters() as schema-element (oa:parameters)
{
  validate {
    <oa:parameters>
    {
      (: 1.  In the HTTP Authorization header as defined in OAuth HTTP Authorization Scheme (OAuth HTTP Authorization Scheme). :)
      let $authorization-header := http:get-header("AUTHORIZATION")
      return
        if (fn:empty($authorization-header)) then
          ()
        else
          let $oauth-parameters-string := fn:substring($authorization-header, 7) (: remove "OAuth " at the beginning of the header :)
          let $oauth-parameters := fn:tokenize ($oauth-parameters-string, ",")
          return
            for $parameter in $oauth-parameters
            return
              let $name-value := fn:tokenize($parameter, "=")
              let $name := utils:decode-from-uri(fn:normalize-space($name-value[1]))
              let $normalized-value := fn:normalize-space($name-value[2])
              let $value-len := fn:string-length($normalized-value)
              let $value := utils:decode-from-uri(fn:substring($normalized-value, 2, ($value-len - 2)))
              return 
                if ($name eq "realm") then
                  ()
                else
                  <oa:parameter name="{ $name }">{ $value }</oa:parameter>
    }
    {
      (: 2. As the HTTP POST request body with a content-type of application/x-www-form-urlencoded. :)
      (: Sausalito http:getParameterNames() does list this parameters automatically :)
      ()
    }
    {
      (: 3. Added to the URLs in the query part :)
      for $parameter-name in http:get-parameter-names()
      return
        let $parameter-value := http:get-parameters($parameter-name)[1]
        return <oa:parameter name="{ $parameter-name }">{ $parameter-value }</oa:parameter>
    }
    </oa:parameters> }
};

(: Internal Functions (Collection) :)

declare function oauth-server:fresh-token() as schema-element (oas:token-pair)
{
  let $token-key := random:random-string($oauth-server:random-length)
  return
    if (fn:empty(xqddf:collection($oauth-server:tokens)[oas:token-key eq $token-key])) then
      let $token-secret := random:random-string($oauth-server:random-length)
      return
        validate {
          <oas:token-pair>
            <oas:token-key>{ $token-key }</oas:token-key>
            <oas:token-secret>{ $token-secret }</oas:token-secret>
          </oas:token-pair>
        }
    else (: this token key is already used --> try again :)
      oauth-server:fresh-token()
};


(:
  Debug / Test Functions
:)

declare function oauth-server:consumers()
{
  xqddf:collection($oauth-server:consumers)
};

declare function oauth-server:tokens()
{
  xqddf:collection($oauth-server:tokens)
};
