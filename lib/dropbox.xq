module namespace dropbox = "http://www.28msec.com/templates/oauth/lib/dropbox";

import module namespace oac="http://www.28msec.com/templates/oauth/lib/oauth/commons";
import module namespace oa="http://www.28msec.com/templates/oauth/lib/oauth/client";
import module namespace json="http://www.zorba-xquery.com/modules/json";
import module namespace functx="http://www.functx.com";
import module namespace zorba-base64="http://www.zorba-xquery.com/modules/base64";

import schema namespace oas="http://www.28msec.com/modules/oauth/client" at "schemas/client.xsd";
import schema namespace dbs="http://www.28msec.com/templates/oauth/schemas/dropbox";


(: the oauth token/secret pair is from our test-app (email: luchind@hotmail.com) :)
declare variable $dropbox:config := 
  oac:config-dropbox("d72mcnqhyv2vijy","tbqk5xodi0rg8r0","http://dropbox.my28msec.com/dbxdemo/callback");
  
 (: oac:config-dropbox("ikz7zu05qb3s7yv","pp841zp52a4b1qy","http://127.0.0.1:8080/dbxdemo/callback"); :)

declare sequential function dropbox:start()
{ 
  oac:init($dropbox:config);
};



   (: ##############################################
   #
   #   Dropbox accounts
   #
   ############################################## :)

(:~
: Retrieves information about the user's account.
:
: @param $locale Use to specify language settings for user error messages 
:  				 and other language specific text.
:
: @return User account information.
:)
declare sequential function dropbox:account-info($locale as xs:string?)
{
  (: assign params :)
  let $params := 
    if (fn:empty($locale)) then
      ()
    else
      validate {
      <oas:parameters>
        <oas:parameter name="locale">{$locale}</oas:parameter>
      </oas:parameters>
      }
      
  (: use our http-request factory function :)
  let $http-request := dropbox:httpRequest("https://api.dropbox.com/1/account/info",(),$params,())
  
  
  (: send signed request for resource :)
  let $response := oac:resource($dropbox:config, $http-request)
  let $status-code := $response/oas:status-code
  let $text := $response/oas:payload/text()

  let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }
  
  return 
  (
    if (fn:empty($json) or $status-code ne 200) then
        dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
    else
        <dbs:account-info>
            <dbs:referral_link>{$json/pair[@name='referral_link']/text()}</dbs:referral_link>
            <dbs:display_name>{$json/pair[@name='display_name']/text()}</dbs:display_name>
            <dbs:uid>{$json/pair[@name='uid']/text()}</dbs:uid>
            <dbs:country>{$json/pair[@name='country']/text()}</dbs:country>
            <dbs:quota_info>
                <dbs:shared>{$json/pair/pair[@name='shared']/text()}</dbs:shared>
                <dbs:quota>{$json/pair/pair[@name='quota']/text()}</dbs:quota>
                <dbs:normal>{$json/pair/pair[@name='normal']/text()}</dbs:normal>
            </dbs:quota_info>
           <dbs:email>{$json/pair[@name='email']/text()}</dbs:email>
        </dbs:account-info>
  )
};




   (: ##############################################
   #
   #   Files and metadata
   #
   ############################################## :)
   
   
(:~
: Download a file from the api-content server.
:
: @param $root The root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $path The path to the file you want to retrieve.
: @param $rev The revision of the file to retrieve. Defaults to the most recent revision.
:
: @error (404) The file wasn't found at the specified path, or wasn't found at the specified rev.
:
: @return The specified file's contents at the requested revision.
:)
declare sequential function dropbox:files($root as xs:string?,
                                          $path as xs:string,
                                          $rev as xs:string?){
    (: Build params :)
    let $params := 
        if (fn:empty($rev)) then
            ()
        else
            <oas:parameters>
                <oas:parameter name="rev">{$rev}</oas:parameter>
            </oas:parameters>    
            
    (: Build URL :)  
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root    
    let $url := fn:concat("https://api-content.dropbox.com/1/files/",$root,"/",dropbox:encode-path($path))
    
    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,'GET',$params,())
    
    (: Send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()
  
    return 
    (
        if ($status-code eq 404) then
           dropbox:error(xs:QName('DROPBOX_FILE_NOT_FOUND'), '', $response)
        else if ($status-code eq 200) then
            $response
        else
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
    )
};

(:~
: Upload a file to Dropbox.
:
: @param $root The root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $file-contents The file contents to be uploaded.
: @param $path The full path to the file you want to write to. This parameter 
:        	   should not point to a folder.
: @param $locale Use to specify language settings for user error messages 
: 				 and other language specific text.
: @param $overwrite This value, either true (default) or false, determines 
:                   what happens when there's already a file at the specified 
:                   path. If true, the existing file will be overwritten by 
:                   the new one. If false, the new file will be automatically 
:                   renamed (for example, test.txt might be automatically renamed 
:                   to test (1).txt). The new name can be obtained from the 
:                   returned metadata.
: @param $parent-rev The revision of the file you're editing. If parent_rev matches 
:					 the latest version of the file on the user's Dropbox, that file 
:					 will be replaced. Otherwise, the new file will be automatically 
:					 renamed (for example, test.txt might be automatically renamed 
:					 to test (conflicted copy).txt). If you specify a revision that 
:					 doesn't exist, the file will not save (error 400). Get the most 
:					 recent rev by performing a call to dropbox:metadata.
:
: @return The metadata for the uploaded file.
:)
declare sequential function dropbox:files_put($root as xs:string?, 
                                              $file-contents as xs:string, 
                                              $path as xs:string,
                                              $locale as xs:string?,
                                              $overwrite as xs:boolean?, 
                                              $parent-rev as xs:string?){
                                                                    
    (: Build params :)     
    (: We have to include the parameters directly in the url because of a bug in the zorba-library. :)            
    let $params-for-url :=
        validate {
        <oas:parameters>
        {
        if (fn:empty($locale)) then
            ()
        else
        <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        {
        if (fn:empty($overwrite)) then
            ()
        else
             <oas:parameter name="overwrite">{$overwrite}</oas:parameter>
        }
        {
        if (fn:empty($parent-rev)) then
            ()
        else
             <oas:parameter name="parent_rev">{$parent-rev}</oas:parameter>
        }
        </oas:parameters>
       }
       
    let $url-params :=
        oa:parameters-in-url-form($params-for-url)
      
    let $params :=
        validate {
        <oas:parameters> 
            <oas:body-payload content-type="text/plain">{$file-contents}</oas:body-payload> 
        </oas:parameters>
     }
  
    (: Build URL :)
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root
    let $url := 
        if ($url-params) then
            fn:concat("https://api-content.dropbox.com/1/files_put/",$root,"/",dropbox:encode-path($path),"?",$url-params)
        else
            fn:concat("https://api-content.dropbox.com/1/files_put/",$root,"/",dropbox:encode-path($path))
    
    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,"POST",$params,())
        
        
    (: Send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()
  
  
    let $json :=
        try{
            json:parse($text)
        } catch * ($errorcode , $description , $value ) {
            ()
        }
    
    return 
    (
     if ($status-code eq 411) then
        dropbox:error(xs:QName('DROPBOX_WRONG_ENCODING'), '', $response)
     else if ($status-code eq 200) then
        dropbox:json-to-metadata($json)
     else
        dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
     )
};
   

(:~
: Retrieve file or folder metadata.
: @param $root The root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $path The path to the file or folder.
: @param $file-limit Default is 10,000. When listing a folder, the service 
:				     will not report listings containing more than the specified 
:				     amount of files and will instead respond with a 406 (Not 
:				     Acceptable) status response.
: @param $hash Each call to /metadata on a folder will return a hash field, 
: 		       generated by hashing all of the metadata contained in that response. 
:			   On later calls to /metadata, you should provide that value via this 
:		       parameter so that if nothing has changed, the response will be a 304 
:			   (Not Modified) status code instead of the full, potentially very large, 
:		       folder listing. This parameter is ignored if the specified path is 
:			   associated with a file or if list=false. A folder shared between two 
:		       users will have the same hash for each user.
: @param list The strings true (default) and false are valid values. 
:			  If true, the folder's metadata will include a contents field with a list 
:			  of metadata entries for the contents of the folder. If false, the contents 
:			  field will be omitted.
: @param include-deleted If this parameter is set to true, then files and folders that 
:					     have been deleted will also be included in the metadata call.
: @param $rev If you include a particular revision number, then only the metadata for 
:			  that revision will be returned.
: @param $locale The metadata returned will have its size field translated based on the 
:				 given locale.
:
: @error (406) There are too many file entries to return.
:
: @return If a hash is provided and it matches the current revision on the server,
: 		  returns 304 Not Changed.
:		  Otherwise, the metadata for the file or folder at the given <path>. If <path> 
: 		  represents a folder and the list parameter is true, the metadata will also 
:		  include a listing of metadata for the folder's contents.
:)
declare sequential function dropbox:metadata($root as xs:string?,
                                             $path as xs:string,
                                             $file-limit as xs:integer?,
                                             $hash as xs:string?,
                                             $list as xs:boolean?,
                                             $include-deleted as xs:boolean,
                                             $rev as xs:string?,
                                             $locale as xs:string?){
                                              
    (: Build params :) 
    let $params :=
    validate {
        <oas:parameters> 
        {
        if (fn:empty($file-limit)) then
            ()
        else
             <oas:parameter name="file_limit">{$file-limit}</oas:parameter>
        }
        {
        if (fn:empty($hash)) then
            ()
        else
             <oas:parameter name="hash">{$hash}</oas:parameter>
        }
        {
        if (fn:empty($list)) then
            ()
        else
             <oas:parameter name="list">{$list}</oas:parameter>
        }
        <oas:parameter name="include_deleted">{fn:boolean($include-deleted)}</oas:parameter>
        {
        if (fn:empty($rev)) then
            ()
        else
             <oas:parameter name="rev">{$rev}</oas:parameter>
        }
        {
        if (fn:empty($locale)) then
            ()
        else
        <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
     }

    (: Build URL :)
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root
    let $url := fn:concat("https://api.dropbox.com/1/metadata/",$root,"/",dropbox:encode-path($path))
    
    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,'GET',$params,())
     
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }
  
    return 
    (
        if ($status-code = 304) then
            <dbs:status-code>304 Not Modified</dbs:status-code>
        else if (fn:empty($json) or $status-code ne 200) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
            dropbox:json-to-metadata($json)
    )
};


(:~
: Obtain metadata for the previous revisions of a file.
:
: @param $root The root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $path The path to the file.
: @param $rev-limit Default is 10. Max is 1,000. When listing a file, the service will 
:					not report listings containing more than the amount specified and 
:					will instead respond with a 406 (Not Acceptable) status response.
: @param $locale The metadata returned will have its size field translated based on the 
:				 given locale.
:
: @error (406) There are too many file entries to return.
:
: @return A list of all revisions formatted just like file metadata. 
:
:)
declare sequential function dropbox:revisions($root as xs:string?,
                                              $path as xs:string,
                                              $rev-limit as xs:integer?,
                                              $locale as xs:string?){
    
    (: Build params :)                           
    let $params :=
    validate {
        <oas:parameters> 
        {
        if (fn:empty($rev-limit)) then
            ()
        else
             <oas:parameter name="rev_limit">{$rev-limit}</oas:parameter>
        }
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
     }                                      
                                              
    (: Build URL :)
    let $root := 
        if (fn:not($root)) then
            "dropbox"
        else
            $root
    let $url :=fn:concat("https://api.dropbox.com/1/revisions/",$root,"/",dropbox:encode-path($path))

    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,'GET',$params,())
     
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json := json:parse(fn:concat('{"data":', $text, "}"))/pair[@name="data"]/item
  
    return 
        (
        if ($status-code = 406) then
            dropbox:error(xs:QName('DROPBOX_TOO_MANY_FILES'), 'Too many file entries to return', $response)
        else if (fn:empty($json)) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
            <dbs:revisions>
                {
                    for $jitem in $json
                    return dropbox:json-to-metadata($jitem)
                }
            </dbs:revisions>
        )
};

(:~
: Restore a file path to a previous version.
:
: @param $root The root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $path The path to the file.
: @param $rev The revision of the file to restore. 
: @param $locale The metadata returned will have its size field translated based on the 
:				 given locale.
:
: @error (404) Unable to find the revision at that path.
:
: @return The metadata of the restored file.
:
:)
declare sequential function dropbox:restore($root as xs:string?,
                                            $path as xs:string,
                                            $rev as xs:string,
                                            $locale as xs:string?){
                                            
    (: Build params :)                           
    let $params :=
    validate {
        <oas:parameters> 
        <oas:parameter name="rev">{$rev}</oas:parameter>
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
     }                                      
                                              
    (: Build URL :)
    let $root := 
        if (fn:not($root)) then
            "dropbox"
        else
            $root
    let $url :=fn:concat("https://api.dropbox.com/1/restore/",$root,"/",dropbox:encode-path($path))

    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,'POST',$params,())
     
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }
    
  
    return 
    (
        if ($status-code = 404) then
            dropbox:error(xs:QName('REV_NOT_FOUND'), 'Unable to find the revision at that path', $response)
        else if (fn:empty($json) or $status-code ne 200) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
           dropbox:json-to-metadata($json)
    )
};


(:~
: Returns metadata for all files&folders that match the search query
: @param $query defines the search string
: @param $root defines the root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $path is the path to the folder in which (following subfolders)
:			   the file you want to retrieve is (default: root).
: @param $filelimit the maximum and default value is 1'000. When listing 
:		            a folder, the service will not report listings containing 
:		            more than file_limit files and will instead respond with 
:		            a 406 (Not Acceptable) status response
: @param include_deleted if set to true, deleted files will also be included 
:						 in the search
: @locale size field is translated according to this parameter if present
:
: @error (406) too many files to return. 
:)
declare sequential function dropbox:search($query as xs:string,
                                           $root as xs:string?,
                                           $path as xs:string?,
                                           $filelimit as xs:integer?,
                                           $include_deleted as xs:boolean?,         
                                           $locale as xs:string? ){
     
     
     (: Check and build param:)
     if (fn:string-length($query) lt 3 or fn:empty($query)) then
        fn:error(xs:QName('BAD_PARAMETER'), fn:concat('Query is too short: ', $query))
     else
        let $params :=
        validate {
            <oas:parameters> 
            {
            <oas:parameter name="query">{$query}</oas:parameter>
            }
            {
            if (fn:empty($filelimit)) then
                ()
            else
                 <oas:parameter name="filelimit">{$filelimit}</oas:parameter>
            }
            {
            if (fn:empty($include_deleted)) then
                ()
            else
                 <oas:parameter name="include_deleted">{$include_deleted}</oas:parameter>
            }
            {
            if (fn:empty($locale)) then
                ()
            else
                <oas:parameter name="locale">{$locale}</oas:parameter>
            }
            </oas:parameters>
         }                       
        
                                              
    (: Build URL :)
    let $root := 
        if (fn:not($root)) then
            "dropbox"
        else
            $root
    let $url :=fn:concat("https://api.dropbox.com/1/search/",$root,"/",dropbox:encode-path($path))

    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,'GET',$params,())
    
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json := 
        dropbox:parse-json-array($text)

  
    return 
        (
        if ($status-code = 406) then
            dropbox:error(xs:QName('DROPBOX_TOO_MANY_FILES'), 'Too many file entries to return', $response)
        else if (fn:not($status-code = 200)) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
            <dbs:searchresult>
                {
                    for $jitem in $json
                    return dropbox:json-to-metadata($jitem)
                }
            </dbs:searchresult>
        )
    
    
          
};


(:~
: Creates and returns a shareable link to files and folders
:
: @param $locale specifies language settings for error messages and other text
: @param $path is the path to the file you want a shareable link to (defaults to root)
: @param $root defines the root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
:)

declare sequential function dropbox:shares($locale as xs:string?,
                                            $path as xs:string?,
                                            $root as xs:string?){

    (: Build params :)                           
    let $params :=
    validate {
        <oas:parameters>         
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
     }                      
    (: Build URL :)    
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root
    let $url := fn:concat("https://api.dropbox.com/1/shares/",$root,"/",dropbox:encode-path($path))
    
    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,'POST',$params,())
    
    (: Send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()
    
    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }    
    return (
        if(fn:empty($json)) then   
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
            <dbs:shared-link>
                <dbs:url>{$json/pair[@name='url']/text()}</dbs:url>
                <dbs:expires>{$json/pair[@name='expires']/text()}</dbs:expires>            
            </dbs:shared-link>
    
    );
};


(:~
: Returns a direct link to the files
:
: @param $locale specifies language settings for error messages and other text
: @param $root defines the root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $path is the path to the file you want a shareable link to (defaults to root).
:)

declare sequential function dropbox:media($locale as xs:string?,
                                            $path as xs:string?,
                                            $root as xs:string?){

    (: Build params :)                           
    let $params :=
    validate {
        <oas:parameters>         
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
     }                      
    (: Build URL :)    
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root
    let $url := fn:concat("https://api.dropbox.com/1/media/",$root,"/",dropbox:encode-path($path))
    
    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url,'POST',$params,())
    
    (: send signed request for resource :)
    
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()
    
    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }    
    return (
        if(fn:empty($json)) then   
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
            <dbs:media-link>
                <dbs:url>{$json/pair[@name='url']/text()}</dbs:url>
                <dbs:expires>{$json/pair[@name='expires']/text()}</dbs:expires>            
            </dbs:media-link>
    
    );
};


(:~
: Gets a thumbnail for an image
:
: @param $format Valid values are JPEG (default) and PNG 
: @param $size: Valid values are small (default), medium, large, s, m, l, xl
				which map to 32x32, 64x64, 128x128, 64x64, 128x128, 640x480, 1024x768 px
: @param $root defines the root relative to which path is specified.
:              Valid values are "sandbox" and "dropbox" (default).
: @param $path The path to the image file you want to thumbnail.
:)
 
declare sequential function dropbox:thumbnails($format as xs:string?,
                                                $size as xs:string?,
                                                $root as xs:string?,
                                                $path as xs:string?){
  
    (: Build parameters:)
    let $params :=
    validate {
        <oas:parameters> 
        {
        if (fn:empty($format)) then
            ()
        else
             <oas:parameter name="format">{$format}</oas:parameter>
        }
        {
        if (fn:empty($size)) then
            ()
        else
             <oas:parameter name="size">{$size}</oas:parameter>        }
        
        </oas:parameters>
        }
        
        (: Build URL :)    
        let $root := 
            if (fn:empty($root)) then
                "dropbox"
            else
                $root
        let $url := fn:concat("https://api.dropbox.com/1/thumbnails/",$root,"/",dropbox:encode-path($path))
                                                  
        (: Build http-request :)
        let $http-request := dropbox:httpRequest($url,'GET',$params,())
     
        (: send signed request for resource :)
        let $response := oac:resource($dropbox:config, $http-request)
        let $status-code := $response/oas:status-code
        let $text := $response/oas:payload/text()

  
        return 
        (
            if ($status-code = 404) then
            	dropbox:error(xs:QName('FILE_NOT_FOUND'),
            				'The file path was not found or the file extension does not allow conversion to a thumbnail', $response) 
            else if ($status-code = 415) then
				dropbox:error(xs:QName('IMAGE_INVALID'),
            				'The image is invalid and cannot be converted to a thumbnail', $response)             
            else if (fn:empty($text)) then
                dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
            else
	            <dbs:thumbnail>
	                <dbs:filetype>{$format}</dbs:filetype>
	                <dbs:contents>{$text}</dbs:contents>
	            </dbs:thumbnail> 
        )
};


   
   (: ##############################################
   #
   #   File operations
   #
   ############################################## :)
   
(:~
: Copies a file or folder to a new location.
:)
declare sequential function dropbox:copy($root as xs:string?,
                                         $from_path as xs:string,
                                         $to_path as xs:string,
                                         $locale as xs:string?)
{
    (: Set default value for root if no value has been specified :)
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root

    (: Build parameters :)                           
    let $parameters :=
    validate {
        <oas:parameters>
            <oas:parameter name="root">{$root}</oas:parameter>
            <oas:parameter name="from_path">{$from_path}</oas:parameter>
            <oas:parameter name="to_path">{$to_path}</oas:parameter>
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
    }
     
    (: Build url :)
    let $url := "https://api.dropbox.com/1/fileops/copy"

    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url, 'POST', $parameters, ())
     
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }
  
    return 
    (
        if ($status-code = 403) then
            dropbox:error(xs:QName('DESTINATION_FILE_ALREADY_EXISTS'), 'There is already a file at the given destination.', $response)
        else if ($status-code = 404) then
            dropbox:error(xs:QName('SOURCE_FILE_NOT_FOUND'), 'The source file wasn&apos;t found at the specified path.', $response)
        else if ($status-code = 406) then
            dropbox:error(xs:QName('TOO_MANY_FILES_INVOLVED'), 'Too many files would be involved in the operation for it to complete successfully. The limit is currently 10,000 files and folders.', $response)
        else if (fn:empty($json) or $status-code ne 200) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
           dropbox:json-to-metadata($json)
    )
};


(:~
: Creates a folder.
:)
declare sequential function dropbox:create_folder($root as xs:string?,
                                                  $path as xs:string,
                                                  $locale as xs:string?)
{
    (: Set default value for root if no value has been specified :)
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root

    (: Build parameters :)                           
    let $parameters :=
    validate {
        <oas:parameters>
            <oas:parameter name="root">{$root}</oas:parameter>
            <oas:parameter name="path">{$path}</oas:parameter>
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
    }
     
    (: Build url :)
    let $url := "https://api.dropbox.com/1/fileops/create_folder"

    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url, 'POST', $parameters, ())
     
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }
  
    return 
    (
        if ($status-code = 403) then
            dropbox:error(xs:QName('FOLDER_ALREADY_EXISTS'), 'There is already a folder at the given destination.', $response)
        else if (fn:empty($json) or $status-code ne 200) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
           dropbox:json-to-metadata($json)
    )
};



(:~
: Deletes a file or folder.
:)
declare sequential function dropbox:delete($root as xs:string?,
                                $path as xs:string,
                                $locale as xs:string?)
{
    (: Set default value for root if no value has been specified :)
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root

    (: Build parameters :)                           
    let $parameters :=
    validate {
        <oas:parameters>
            <oas:parameter name="root">{$root}</oas:parameter>
            <oas:parameter name="path">{$path}</oas:parameter>
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
    }
     
    (: Build url :)
    let $url := "https://api.dropbox.com/1/fileops/delete"

    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url, 'POST', $parameters, ())
     
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }
  
    return 
    (
        if ($status-code = 404) then
            dropbox:error(xs:QName('FILE_NOT_FOUND'), 'No file wasn&apos;t found at the specified path.', $response)
        else if ($status-code = 406) then
            dropbox:error(xs:QName('TOO_MANY_FILES_INVOLVED'), 'Too many files would be involved in the operation for it to complete successfully. The limit is currently 10,000 files and folders.', $response)
        else if (fn:empty($json) or $status-code ne 200) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
           dropbox:json-to-metadata($json)
    )
};


(:~
: Moves a file or folder to a new location.
:)
declare sequential function dropbox:move($root as xs:string?,
                                         $from_path as xs:string,
                                         $to_path as xs:string,
                                         $locale as xs:string?)
{
    (: Set default value for root if no value has been specified :)
    let $root := 
        if (fn:empty($root)) then
            "dropbox"
        else
            $root

    (: Build parameters :)                           
    let $parameters :=
    validate {
        <oas:parameters>
            <oas:parameter name="root">{$root}</oas:parameter>
            <oas:parameter name="from_path">{$from_path}</oas:parameter>
            <oas:parameter name="to_path">{$to_path}</oas:parameter>
        {
        if (fn:empty($locale)) then
            ()
        else
            <oas:parameter name="locale">{$locale}</oas:parameter>
        }
        </oas:parameters>
    }
     
    (: Build url :)
    let $url := "https://api.dropbox.com/1/fileops/move"

    (: Build http-request :)
    let $http-request := dropbox:httpRequest($url, 'POST', $parameters, ())
     
    (: send signed request for resource :)
    let $response := oac:resource($dropbox:config, $http-request)
    let $status-code := $response/oas:status-code
    let $text := $response/oas:payload/text()

    let $json :=
    try{
        json:parse($text)
    } catch * ($errorcode , $description , $value ) {
        ()
    }
  
    return 
    (
        if ($status-code = 403) then
            dropbox:error(xs:QName('DESTINATION_FILE_ALREADY_EXISTS'), 'There is already a file at the given destination, or an invalid move operation was attempted (e.g. moving a shared folder into a shared folder).', $response)
        else if ($status-code = 404) then
            dropbox:error(xs:QName('SOURCE_FILE_NOT_FOUND'), 'The source file wasn&apos;t found at the specified path.', $response)
        else if ($status-code = 406) then
            dropbox:error(xs:QName('TOO_MANY_FILES_INVOLVED'), 'Too many files would be involved in the operation for it to complete successfully. The limit is currently 10,000 files and folders.', $response)
        else if (fn:empty($json) or $status-code ne 200) then
            dropbox:error(xs:QName('DROPBOX_HTTP_RESPONSE_ERROR'), 'Bad response from Dropbox server', $response)
        else
           dropbox:json-to-metadata($json)
    )
};  
   
   
   
   (: ##############################################
   #
   #   Util
   #
   ############################################## :)

(:~
: 
: OAuth-http-request factory method.
:
: @param $url the url of the http-request
: @param $method? (default: GET) the method (GET or POST) of the http-request
: @param $params? (default: ()) the params of the http-request
: @param $headers? (default: ()) the headers of the http-request
: @param $body? (default: ()) the body of the http-request
:)
declare function dropbox:httpRequest($url as xs:string, 
                                                $method as xs:string?, 
                                                $params as schema-element(oas:parameters)?,
                                                $headers as schema-element(oas:headers)?) 
                                                as schema-element (oas:http-request)
{
    validate {
   <oas:http-request>
   {
       if ($method eq "POST") then
         <oas:http-method>POST</oas:http-method>
       else
       (: default to GET :)
         <oas:http-method>GET</oas:http-method>
   }   
        <oas:target-url>{$url}</oas:target-url>
   {
       if (fn:not(fn:empty($params))) then
         $params
       else 
         ()
   }
   {
       if (fn:not(fn:empty($headers))) then
         $headers
       else 
         ()
   }
   </oas:http-request>
   }
};

(:~
: 
: Parses a json-array, i.e. a json-object containing a json-array of json-objects,
: in the form: [{...}, {...}, {...}]
:
: @param $json-array the json-array string to parse
: @return () if an error happened or the array is empty - otherwise, a  
:         sequence of json-objects which were parsed from the input array
:)

declare function dropbox:parse-json-array($json-array as xs:string){

    let $json-strings :=
        functx:get-matches( $json-array, '\{[^}]+\}')
  
    let $json :=
     try{
        for $item in $json-strings
        where $item ne ""
        return json:parse($item)
        } catch * ($errorcode , $description , $value ) {
            ()
        }
        
    return $json
};


declare function dropbox:json-to-metadata($json){
    <dbs:metadata>
            {
                if ($json/pair[@name='hash']) then
                    <dbs:hash>{$json/pair[@name='hash']/text()}</dbs:hash>
                else 
                    ()
            }
            {
                if ($json/pair[@name='is_deleted']) then
                    <dbs:is_deleted>{$json/pair[@name='is_deleted']/text() = "true"}</dbs:is_deleted>
                else 
                    ()
            }
            <dbs:rev>{$json/pair[@name='rev']/text()}</dbs:rev>
            <dbs:thumb_exists>{$json/pair[@name='thumb_exists']/text() = "true"}</dbs:thumb_exists>
            <dbs:bytes>{fn:number($json/pair[@name='bytes']/text())}</dbs:bytes>
            <dbs:modified>{$json/pair[@name='modified']/text()}</dbs:modified>
            <dbs:path>{$json/pair[@name='path']/text()}</dbs:path>
            <dbs:is_dir>{$json/pair[@name='is_dir']/text() = "true"}</dbs:is_dir>
            <dbs:icon>{$json/pair[@name='icon']/text()}</dbs:icon> 
            <dbs:root>{$json/pair[@name='root']/text()}</dbs:root> 
            <dbs:mime_type>{$json/pair[@name='mime_type']/text()}</dbs:mime_type> 
            <dbs:size>{$json/pair[@name='size']/text()}</dbs:size>
            {
                if ($json/pair[@name='contents']/item) then
                <dbs:contents>
                    {
                        for $item in $json/pair[@name='contents']/item
                        let $metadata := dropbox:json-to-metadata($item)
                        return $metadata
                    }
                </dbs:contents>
                else 
                    ()
            }
        </dbs:metadata>
};

declare sequential function dropbox:error($errcode as xs:QName, $desc as xs:string, $reply){

    let $payload :=
        if (fn:empty($reply/oas:payload/text())) then
            ()
        else
            try{
                zorba-base64:decode($reply/oas:payload/text())
        } catch * ($errorcode , $description , $value ) {
                $reply/oas:payload/text()
        }
      
    let $description := 
        if (fn:empty($payload)) then
           fn:concat($desc, ' (', $reply/oas:status-code, ')')
        else
           fn:concat($desc, ' (', $reply/oas:status-code, ') - ', $payload)
            
    return (
          fn:error(xs:QName($errcode),$description)    
    )
};


declare function dropbox:encode-path($path as xs:string) {
    (: The following characters are not allowed in dropbox file names:  \ / : ? * < > " |  :)
    (: $&+,;=@ #%{}^~[]` :)
    let $special :=
        ("%"  ,  "\$", "&amp;", "\+" , ","  , ";"  , "="  , "@"  , " "  , "#"  , "\{" , "\}" , "\^" , "~"  , "\[" , "\]" , "`")
    let $special-encoded :=
        ("%25", "%24", "%26"  , "%2B", "%2C", "%3B", "%3D", "%40", "%20", "%23", "%7B", "%7D", "%5E", "%7E", "%5B", "%5D", "%60")
    
    return functx:replace-multi($path, $special, $special-encoded)
};
