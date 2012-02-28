(:
 : Copyright 2010 28msec Inc.
 :)

(:~
 :
 : The OAuth module allows you to access protected resources on a service provider that
 : supports OAuth.
 :
 : @see http://www.oauth.net
 :)
module namespace oauth="http://www.28msec.com/templates/oauth/lib/oauth/client";

import module namespace utils="http://www.28msec.com/modules/utils";
import module namespace random="http://www.28msec.com/modules/random";
import module namespace http="http://www.28msec.com/modules/http";
import module namespace http-client="http://expath.org/ns/http-client";
import module namespace zorba-rest = "http://www.zorba-xquery.com/zorba/rest-functions";
import module namespace oac="http://www.28msec.com/modules/oauth/client";
import module namespace zorba-ser="http://www.zorba-xquery.com/modules/serialize";
import module namespace zorba-base64="http://www.zorba-xquery.com/modules/base64";

declare namespace xhtml="http://www.w3.org/1999/xhtml";

import schema namespace oa="http://www.28msec.com/modules/oauth/client" at "schemas/client.xsd";

(: ##############################################
   #
   #   OAuth process functions
   #
   ############################################## :)

(:~
 :
 : Receive a request token (and token secret) from the service-provider. 
 : Specify the callback URL and additional parameters as maybe requested by the service provider. 
 :
 : @param $service-provider The service provider structure
 : @param $callback-url The callback URL the service provider has to use after the authorization process
 : @param $parameters Additional parameters that may be requested by the service provider
 : @param $headers Additional headers that may be requested by the service provider
 : @return A token pair containg the requested token (request token)
 : @error Unconfirmed Callback URL
 : @error Invalid OAuth authentication
 :)
declare function oauth:request-token($service-provider as schema-element (oa:service-provider), 
                                     $callback-url as xs:string?, 
                                     $parameters as schema-element (oa:parameters)?,
                                     $headers as schema-element (oa:headers)?) as schema-element (oa:token-pair)
{
  let $url := $service-provider/oa:request-token/oa:url/text()
  let $http-method := fn:upper-case($service-provider/oa:request-token/oa:http-method/text())
  let $additional-oauth-headers :=
    if (fn:empty($callback-url)) then
      ()
    else
      validate { 
        <oa:parameters>
          <oa:parameter name="oauth_callback">{ $callback-url }</oa:parameter>
        </oa:parameters> }
  let $authorization-header := oauth:authorization-header($service-provider,
                                                          $http-method,
                                                          $url,
                                                          (),
                                                          $additional-oauth-headers,
                                                          $parameters )
  let $http-request := trace(
    <oa:http-request>
      <oa:http-method>{ $http-method }</oa:http-method>
      <oa:target-url>{ $url }</oa:target-url>
      {
        $parameters
      }
      <oa:headers>
      { 
        $authorization-header,
        $headers/oa:header
      }
      </oa:headers>
    </oa:http-request>
                        , "http-request")
    
   let $http-response := oauth:http-request( validate { $http-request }, fn:true()) 
  
  
  let $payload-response := validate { trace($http-response/oa:payload/node(),"http-response-payload") }
  return 
  trace(
    if (fn:empty($payload-response/oa:oauth_callback_confirmed)) then
      $payload-response
    else
      if (fn:upper-case($payload-response/oa:oauth_callback_confirmed/text()) eq "TRUE") then
        $payload-response
      else
        fn:error(xs:QName('OAUTH_REQUEST_TOKEN_CALLBACK_CONFIRMATION'), "Callback URL not confirmed", $payload-response), "bla")       
};

(:~
 :
 : Redirects to the authorization page of the service provider. 
 : After log in and grant access, the service provider redirects the user to the callback URL specified and returns token and verifier values. 
 :
 : @param $service-provider The service provider structure
 : @param $request-token-pair The token pair received during the request token process
 : @param $parameters Additional parameters that may be requested by the service provider
 : @return Empty sequence (consumer will be redirected to the service providers authorization URL)
 :)
declare sequential function oauth:user-authorization($service-provider as schema-element (oa:service-provider), 
                                          $request-token-pair as schema-element (oa:token-pair)?,
                                          $parameters as schema-element (oa:parameters)?)
{
  let $url := oauth:user-authorization-url($service-provider, $request-token-pair, $parameters)
  return http:set-redirect($url)
};

(:~
 :
 : Does not redirect, but returns the authorization URL instead (for manual redirect or link creation).
 :
 : @param $service-provider The service provider structure
 : @param $request-token-pair The token pair received during the request token process
 : @param $parameters Additional parameters that may be requested by the service provider
 : @return The service providers authorization URL
 :)
declare function oauth:user-authorization-url($service-provider as schema-element (oa:service-provider), 
                                              $request-token-pair as schema-element (oa:token-pair)?,
                                              $parameters as schema-element (oa:parameters)?) as xs:string
{  
  let $authorization-url := $service-provider/oa:user-authorization/oa:url/text()
  let $url-additional-params := oauth:parameters-in-url-form($parameters)
  let $request-token := $request-token-pair/oa:token/text()
  let $request-token-param :=
    if (fn:empty($request-token)) then
      ()
     else
      fn:concat("oauth_token=", $request-token)
  let $url-params := fn:string-join( ($request-token-param, $url-additional-params), "&amp;" )
  let $redirection-url := 
    if (fn:contains($authorization-url, "?")) then
      fn:string-join( ($authorization-url, $url-params), "&amp;" )
    else
    fn:string-join( ($authorization-url, $url-params), "?" )
  return $redirection-url
};

(:~
 :
 : Exchange the request token &amp; token secret (and verifier) for an access token &amp; token secret.
 :
 : @param $service-provider The service provider structure
 : @param $request-token-pair The token pair received during the request token process
 : @param $verifier Verifier received from the service provider after user authorization
 : @return A token pair containg the requested token (access token)
 : @error Invalid OAuth authentication
 :)
declare function oauth:access-token($service-provider as schema-element (oa:service-provider), 
                                    $request-token-pair as schema-element (oa:token-pair), 
                                    $verifier as xs:string?) as schema-element (oa:token-pair)
{
  let $url := $service-provider/oa:access-token/oa:url/text()
  let $http-method := fn:upper-case($service-provider/oa:access-token/oa:http-method/text())
  let $additional-oauth-headers := 
    if (fn:string-length($verifier) eq 0) then
      ()
    else
      validate {
      <oa:parameters>
        <oa:parameter name="oauth_verifier">{ $verifier }</oa:parameter>
      </oa:parameters> }
  let $authorization-header := oauth:authorization-header($service-provider,
                                                          $http-method,
                                                          $url,
                                                          $request-token-pair,
                                                          $additional-oauth-headers,
                                                          () )
  let $http-request :=
    <oa:http-request>
      <oa:http-method>{ $http-method }</oa:http-method>
      <oa:target-url>{ $url }</oa:target-url>
      <oa:headers>
        { $authorization-header }
      </oa:headers>
    </oa:http-request>
  let $http-response := oauth:http-request(validate { $http-request }, fn:true())
  return validate { $http-response/oa:payload/node() }
};

(:~
 :
 : Access to the protected resource. HTTP-Method, URL, Parameters and Header according the service provider specification.
 :
 : @param $service-provider The service provider structure
 : @param $http-request A http request structure specifying what and how to access the resource
 : @param $access-token-pair The token pair received during the access token process
 : @return HTTP response containing the requested information
 : @error Invalid OAuth authentication
 :)
declare sequential function oauth:protected-resource($service-provider as schema-element (oa:service-provider), 
                                          $http-request as schema-element (oa:http-request),
                                          $access-token-pair as schema-element (oa:token-pair)) as schema-element (oa:http-response)
{  
  let $parameters :=
    if (fn:empty($http-request/oa:parameters)) then
      ()
    else
      $http-request/oa:parameters
  let $authorization-header := oauth:authorization-header($service-provider,
                                                          oauth:http-method ($http-request),
                                                          oauth:target-url ($http-request),
                                                          $access-token-pair,
                                                          (),
                                                          $parameters)
  let $modified-http-request :=
      <oa:http-request>
        {
          $http-request/oa:http-method,
          $http-request/oa:target-url,
          $http-request/oa:parameters
        }
        <oa:headers>
        { 
          $authorization-header,
          $http-request/oa:headers/oa:header
        }
        </oa:headers>
      </oa:http-request>
  let $http-response := oauth:http-request(validate { $modified-http-request }, fn:false())
  let $status-code := fn:number($http-response/oa:status-code)  
  return
    if ($status-code eq 302) then (: Moved temporarily :)
      let $redirection-url := $http-response/oa:headers/oa:header[@name eq "Location"]/text()
      (: does the redirection url already contain all the parameters? :)
      let $remove-parameters := oauth:contains-parameter($redirection-url, $http-request/oa:parameters)
      return 
        block {
          replace value of node $http-request/oa:target-url with $redirection-url;
          (
            if ($remove-parameters) then
              delete node $http-request/oa:parameters
            else
              ()
          );
          oauth:protected-resource($service-provider, validate { $http-request }, $access-token-pair);
         }
    else
        $http-response
};


(: ##############################################
   #
   #   Internal functions
   #
   ############################################## :)

(: checks if every parameter in $parameters is also contained as a parameter in the $url (twice the same name/value pair is not checked) :)
declare function oauth:contains-parameter ($url as xs:string, $parameters as schema-element (oa:parameters)?) as xs:boolean
{
  let $url-parameters := <oa:parameters>{ oauth:extract-get-url-parameters($url) }</oa:parameters>
  let $comparison :=
    for $param in $parameters/oa:parameter
    return fn:not(fn:empty($url-parameters/oa:parameter[@name eq $param/@name and text() eq $param/text()]))
  return fn:not($comparison = fn:false())
};


(: returns the base string for according to the OAuth spec :)
declare function oauth:base-string($http-method as xs:string, 
                                   $url as xs:string, 
                                   $parameters as schema-element (oa:parameters)) as xs:string
{
  let $encoded-parameters := oauth:encode-parameters($parameters)
  let $sorted-parameters := oauth:sort-parameters($encoded-parameters)
  let $request-url := oauth:construct-request-url($url)
  let $request-params := 
    for $param in $sorted-parameters/oa:parameter
    return fn:concat(fn:data($param/@name), "=", $param/text())
  let $normalized-request-parameters := fn:string-join($request-params, "&amp;")
  let $parts := 
  (
    fn:encode-for-uri(fn:upper-case($http-method)),
    fn:encode-for-uri($request-url),
    fn:encode-for-uri($normalized-request-parameters)
  )
  return fn:string-join($parts, "&amp;")
  
};

(: parse the response from the request token and access token http requests and returns an xml element :)
declare function oauth:parse-token-response-payload($payload-text as xs:string) as schema-element (oa:token-pair)
{
  let $parameters := fn:tokenize($payload-text, "&amp;")
  let $params-unsorted := 
    <unsorted>
    {
      for $parameter in $parameters
      return
        let $param-parts := fn:tokenize($parameter, "=")
        let $name := utils:decode-from-uri($param-parts[1])
        let $value := utils:decode-from-uri($param-parts[2])
        return element { fn:concat( "oa:", $name) } { $value }
    }
    </unsorted>
  return
    if (fn:empty($params-unsorted/oa:oauth_token) or fn:empty($params-unsorted/oa:oauth_token_secret)) then
      fn:error(xs:QName('OAUTH_PARSE_TOKEN_RESPONSE_PAYLOAD'), "Missing token / token secret in response payload", $payload-text)    
    else
      validate {
        <oa:token-pair>
          <oa:token>{ $params-unsorted/oa:oauth_token/text() }</oa:token>
          <oa:token-secret>{ $params-unsorted/oa:oauth_token_secret/text() }</oa:token-secret>
          { $params-unsorted/*[fn:not(fn:local-name(.) eq "oauth_token" or fn:local-name(.) eq "oauth_token_secret")] }  
        </oa:token-pair> }
};

(: encode the parameter names and values according to OAuth (URL Encoding) :)
declare function oauth:encode-parameters($parameters as schema-element (oa:parameters)) as schema-element (oa:parameters)
{
  validate {
  <oa:parameters>
  {
    for $parameter in $parameters/oa:parameter
    return <oa:parameter name="{ fn:encode-for-uri(fn:data($parameter/@name)) }">{ fn:encode-for-uri($parameter/text()) }</oa:parameter>
  }
  </oa:parameters> }
};

(: sort the parameters ascending by name, then ascending by value :)
declare function oauth:sort-parameters($parameters as schema-element (oa:parameters)) as schema-element (oa:parameters)
{
  validate {
  <oa:parameters>
  {
    for $parameter in $parameters/oa:parameter
    order by fn:data($parameter/@name) ascending, $parameter/text() ascending
    return $parameter
  }
  </oa:parameters> }
};

(: transforms the oa:parameters into zorba style parameters (for rest call) :)
declare function oauth:zorba-style-parameters($parameters as schema-element (oa:parameters))
{
  for $parameter in $parameters/oa:parameter
  return <part name="{ fn:data($parameter/@name) }">{ $parameter/text() }</part>
};

(: make the http request :)
declare function oauth:http-request($http-request as schema-element (oa:http-request), $is-token-response as xs:boolean) as schema-element (oa:http-response)
{
  let $http-method := oauth:http-method ($http-request)
  let $target-url := oauth:target-url (trace($http-request, "http-request"))
  let $headers := $http-request/oa:headers
  let $request-parameters := $http-request/oa:parameters
  let $parameters :=
    if (fn:empty($request-parameters/oa:body-payload/node())) then (: empty body payload :)
      if (fn:empty($request-parameters/oa:parameter)) then
        ()
      else
        <payload content-type="multipart/form-data">{ oauth:zorba-style-parameters($request-parameters) }</payload>
    else (: body payload not empty :)
      if (fn:empty($request-parameters/oa:parameter)) then
        <payload>
        {
          $request-parameters/oa:body-payload/@content-type,
          $request-parameters/oa:body-payload/node()
        }
        </payload>
      else
        <payload content-type="multipart/form-data">
          { oauth:zorba-style-parameters($request-parameters) }
          <part>
          {
            $request-parameters/oa:body-payload/@content-type,
            $request-parameters/oa:body-payload/node()
          }
          </part>
        </payload>
  let $zorba-response := (: use tidy if token response expected :)
    if ($http-method eq "GET") then
      if ($is-token-response) then
        zorba-rest:getTidy($target-url, "", $parameters, $headers)
      else
        zorba-rest:get($target-url, $parameters, $headers)
    else if ($http-method eq "POST") then
      if ($is-token-response) then
        zorba-rest:postTidy($target-url, "", $parameters, $headers)
      else
        zorba-rest:post($target-url, $parameters, $headers)
    else if ($http-method eq "PUT") then
      zorba-rest:put($target-url, $parameters, $headers)
    else if ($http-method eq "DELETE") then
      zorba-rest:delete($target-url, $parameters, $headers)
    else if ($http-method eq "HEAD") then
      zorba-rest:head($target-url, $parameters, $headers)
    else 
      fn:error(xs:QName('OAUTH_HTTP_REQUEST'), fn:concat("Unsupported HTTP Method ", $http-method), $http-request) 
  let $status-code := trace(fn:number($zorba-response/zorba-rest:status-code), "response status code")  
  let $zorba-response := trace($zorba-response, "zorba-response")
  return
    validate {
      <oa:http-response>
        <oa:status-code>{ $status-code }</oa:status-code>
        {
          if (fn:empty($zorba-response/zorba-rest:headers/zorba-rest:header)) then
            ()
          else
            <oa:headers>
            {  
              for $header in $zorba-response/zorba-rest:headers/zorba-rest:header
              return <oa:header name="{ fn:data($header/@zorba-rest:name) }">{ $header/text() }</oa:header>
            }
            </oa:headers>
        }
        <oa:payload>
        {
          if ($is-token-response) then
          (
            if ($status-code eq 200) then
            (
              let $token-text := 
                if (fn:empty($zorba-response/zorba-rest:payload/xhtml:html)) then (: was tidy involved :)
                  if (fn:contains($target-url, "dropbox")) then
                    (: dropbox call - we need to decode the payload :)
                    trace(zorba-base64:decode($zorba-response/zorba-rest:payload/text()), "decoded payload")
                  else
                    $zorba-response/zorba-rest:payload/text()
                else (: yes, get only html body (and remove newlines at the beginning and at the end) :)
                  fn:normalize-space($zorba-response/zorba-rest:payload/xhtml:html/xhtml:body/text())
              return oauth:parse-token-response-payload($token-text)
            )
            else
              let $error-message := fn:concat( "The service provider returned status code ", $status-code, " (", $zorba-response/zorba-rest:payload/text(), ")" )
              return fn:error(xs:QName('OAUTH_HTTP_REQUEST_TOKEN_RESPONSE'), $error-message, $zorba-response)    
          )
          else
            $zorba-response/zorba-rest:payload/node()
        }
        </oa:payload>
      </oa:http-response> }
};

(: constructing the request url according to the oauth spec :)
declare function oauth:construct-request-url($url as xs:string) as xs:string
{
  (: http://Example.com:80/resource?id=123 :)
  let $url-parts := fn:tokenize($url, "://")
  let $scheme := fn:lower-case($url-parts[1])
  let $authority-port-path-query-fragment := fn:tokenize($url-parts[2], "\?")
  let $authority-port-path := fn:tokenize($authority-port-path-query-fragment[1], "/")
  let $path := 
    fn:string-join(
      for $i in (2 to fn:count($authority-port-path))
      return $authority-port-path[$i],
      "/"
    )
  let $authority-port := fn:tokenize($authority-port-path[1], ":")
  let $port := $authority-port[2]
  let $authority := fn:lower-case($authority-port[1])
  let $port-part :=
    if (fn:empty($port)) then
      ()
    else
      if (($scheme eq "http" and $port eq "80") or ($scheme eq "https" and $port eq "443")) then
        ()
      else
        fn:concat(":", $port)  
  return fn:concat($scheme, "://", $authority, $port-part, "/", $path)  
};

(: external function for signature generation :)
declare function oauth:signature($base-string as xs:string, 
                                 $signature-method as xs:string, 
                                 $key as xs:string) as xs:string {
                                 oac:signature($base-string,$signature-method,$key);
                                 };


(: timestamp: number of seconds since 1970/01/01 :)
declare function oauth:timestamp() as xs:decimal
{
  let $current-dateTime := fn:adjust-dateTime-to-timezone(fn:current-dateTime(), xs:dayTimeDuration('PT0H'))
  let $duration := $current-dateTime - xs:dateTime("1970-01-01T00:00:00Z")
  return fn:round($duration div xs:dayTimeDuration('PT1S'))
};

(: 
  Random 64-bit, unsigned number encoded as an ASCII string in decimal format (nonce defined by Google)
  In fact, just a random mixed string could be used, but this works as well.
:)
declare function oauth:nonce() as xs:integer
{
  let $seq-255 := (1, 255, 65025, 16581375, 4228250625, 1078203909375, 274941996890625, 70110209207109375)
  let $random-byte-sequence := 
    for $i in 1 to 8
    let $random := random:random-uniform(xs:int(0), xs:int(255))  
    let $result := $random * $seq-255[$i]
    return $result
  return fn:sum($random-byte-sequence)
};

(: parameters in url form (name=value&name2=value2) :)
declare function oauth:parameters-in-url-form($parameters as schema-element (oa:parameters)?) as xs:string*
{
  if (fn:empty($parameters/oa:parameter)) then (: body might contain something, but this is ignored :)
    ()
  else
    for $param in $parameters/oa:parameter
    return fn:concat(fn:encode-for-uri(fn:data($param/@name)), "=", fn:encode-for-uri($param/text()))    
};

(: parameters for oauth authorization header according to http://oauth.net/core/1.0a#auth_header :)
declare function oauth:parameters-in-oauth-header-form($parameters as schema-element (oa:parameters)?) as xs:string*
{
    for $param in $parameters/oa:parameter
    return fn:concat(fn:encode-for-uri(fn:data($param/@name)), "=&quot;", fn:encode-for-uri($param/text()), "&quot;")    
};


(: authorization header for signed oauth requests :)
declare function oauth:authorization-header($service-provider as schema-element (oa:service-provider),
                                            $http-method as xs:string,
                                            $url as xs:string,
                                            $token-pair as schema-element (oa:token-pair)?,
                                            $additional-oauth-parameters as schema-element (oa:parameters)?,
                                            $additional-parameters as schema-element (oa:parameters)?)
{
  let $signature-method := oauth:signature-method($service-provider)
  let $token := $token-pair/oa:token/text()
  let $token-secret := $token-pair/oa:token-secret/text()
  let $additional-parameters-extracted :=
    (
      $additional-parameters/oa:parameter,
      oauth:extract-get-url-parameters($url),
      oauth:extract-http-body-parameters($additional-parameters/oa:body-payload)
    )
  let $consumer-key := oauth:consumer-key($service-provider)
  let $nonce := oauth:nonce()
  let $parameters_for_signature :=
    <oa:parameters>      
      <oa:parameter name="oauth_consumer_key">{ $consumer-key }</oa:parameter>
      {
        if (fn:empty($token)) then
          ()
        else
          <oa:parameter name="oauth_token">{ $token }</oa:parameter>
      }
      <oa:parameter name="oauth_signature_method">{ $signature-method }</oa:parameter>      
      <oa:parameter name="oauth_timestamp">{ oauth:timestamp() }</oa:parameter>
      <oa:parameter name="oauth_nonce">{ $nonce }</oa:parameter>
      {
        if (fn:empty($service-provider/oa:oauth-version/text())) then
          ()
        else
          <oa:parameter name="oauth_version">{ $service-provider/oa:oauth-version/text() }</oa:parameter>
      }      
      { $additional-oauth-parameters/oa:parameter }
      { $additional-parameters-extracted }
    </oa:parameters>
  let $base-string := oauth:base-string($http-method, $url, validate { $parameters_for_signature })  
  let $key := oauth:signing-key-for-signature-method($signature-method, $service-provider, $token-secret)
  let $signature := oauth:signature($base-string, $signature-method, $key)
  let $params_for_header :=
    <oa:parameters>
      <oa:parameter name="realm">{ fn:data($service-provider/@realm) }</oa:parameter>
      { $parameters_for_signature/oa:parameter[fn:starts-with(fn:data(@name), "oauth_")] }
      <oa:parameter name="oauth_signature">{ $signature }</oa:parameter>
    </oa:parameters>
  return <oa:header name="Authorization">{ fn:concat("OAuth ", fn:string-join(oauth:parameters-in-oauth-header-form(validate { $params_for_header }), ", ")) }</oa:header>  
};

(: returns the signing key according to the signature method specified :)
declare function oauth:signing-key-for-signature-method($signature-method as xs:string, 
                                                        $service-provider as schema-element (oa:service-provider), 
                                                        $token-secret as xs:string?) as xs:string
{
  let $predefined_key := $service-provider/oa:authentication/oa:signature-method[@name eq $signature-method]
  let $key :=
    if (fn:empty($predefined_key)) then
      let $consumer-secret := oauth:consumer-key-secret($service-provider)
      return fn:concat(fn:encode-for-uri($consumer-secret), "&amp;", fn:encode-for-uri($token-secret))
    else
      $predefined_key/text()
  return $key
};

(: extract parameters from an url :)
declare function oauth:extract-get-url-parameters($url as xs:string?)
{
  let $url-parts := fn:tokenize($url, "\?")
  return oauth:extract-url-parameters($url-parts[2])
};

(: extract parameters from the body (if content type is application/x-www-form-urlencoded) :)
declare function oauth:extract-http-body-parameters($body-payload)
{
  let $content-type := fn:data($body-payload/@content-type)
  return
    if ($content-type eq "application/x-www-form-urlencoded" ) then
      oauth:extract-url-parameters($body-payload)
    else
      ()
};

(: extract parameters from a parameter string :)
declare function oauth:extract-url-parameters($parameters as xs:string?)
{
  let $params := fn:tokenize($parameters, "&amp;")
  return
    for $param in $params
    return 
      let $name-value := fn:tokenize($param, "=")
      let $name := utils:decode-from-uri($name-value[1])
      let $value := utils:decode-from-uri($name-value[2])
      return <oa:parameter name="{ $name }">{ $value }</oa:parameter>
};

(: HTTP Request Accessors :)

declare function oauth:http-method ($http-request as schema-element (oa:http-request)) as xs:string
{
  let $http-method := $http-request/oa:http-method/text()
  return
    if (fn:empty($http-method)) then
      "GET"
    else
      $http-method
};

declare function oauth:target-url ($http-request as schema-element (oa:http-request)) as xs:string
{
  $http-request/oa:target-url/text()
};

(: Service Provider Accessors :)

declare function oauth:signature-method($service-provider as schema-element (oa:service-provider)) as xs:string
{
  fn:upper-case(($service-provider/oa:supported-signature-methods/oa:method/text())[1])
};

declare function oauth:consumer-key($service-provider as schema-element (oa:service-provider)) as xs:string
{
  $service-provider/oa:authentication/oa:consumer-key/text()
};

declare function oauth:consumer-key-secret($service-provider as schema-element (oa:service-provider)) as xs:string
{
  $service-provider/oa:authentication/oa:consumer-key-secret/text()
};
