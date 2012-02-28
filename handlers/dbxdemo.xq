(: A simple dropbox browser :)

module namespace dbxdemo = "http://www.28msec.com/templates/oauth/dbxdemo";

import module namespace oac="http://www.28msec.com/templates/oauth/lib/oauth/commons";

import module namespace dropbox = "http://www.28msec.com/templates/oauth/lib/dropbox"; 
import module namespace http="http://www.28msec.com/modules/http";
import module namespace functx="http://www.functx.com";
import module namespace zorba-base64="http://www.zorba-xquery.com/modules/base64";

import schema namespace oas="http://www.28msec.com/modules/oauth/client" at "schemas/client.xsd";
import schema namespace dbs="http://www.28msec.com/templates/oauth/schemas/dropbox";

declare sequential function dbxdemo:start(){
	dropbox:start()
};

declare sequential function dbxdemo:callback(){

  oac:callback($dropbox:config),
    <html>
    <head>
    <script language="JavaScript" type="text/javascript"/>
      <title>OAuth Callback</title>
    </head>
    <body onload="document.location='/dbxdemo/browse'">
      <p>Authentication procedure completed. Starting demo... </p>
      <p><a href="/dbxdemo/browse/">Click here</a> if the demo doesn't load automatically</p>
    </body>
  </html>
};
	

declare sequential function dbxdemo:index()
{
	dbxdemo:browse()
};

declare function dbxdemo:render($title as xs:string,
                                $content) {
<html>
    <head>
        <title>{$title}</title>
        <link href="/dbxdemo.css" rel="stylesheet" type="text/css" />
        <script src="/dbxdemo.js"></script>
    </head>
    <body>
        {$content}
    </body>
</html>
};

declare sequential function dbxdemo:browse() {
    (: get the path from the http request :)
    let $path := http:get-parameters("path", "")
    
    (: get metadata for path :)
    let $metadata_path := ()
    
    let $response := dropbox:metadata("sandbox", $path,(),(),(),fn:true(),(),())
    
    let $browser-header :=
        <div class="browser-header">
            {dbxdemo:header-path($path,($response/dbs:is_dir = fn:true()))}
        </div>
    
    let $browser-content := 
        if ($response/dbs:contents) then
            for $item in $response/dbs:contents/dbs:metadata
                return if ($item/dbs:is_dir = fn:true()) then
                    dbxdemo:displayAsFolder($item/dbs:path, ($item/dbs:is_deleted = fn:true()))
                else
                    dbxdemo:displayAsFile($item/dbs:path, ($item/dbs:is_deleted = fn:true()))
        else
            ()
            
    let $path-encoded := dropbox:encode-path($path)
    
    let $browser-footer :=
        <div class="browser-footer">
            <a class="browser-action" href="addfolder?path={$path-encoded}">add folder</a>
            <a class="browser-action" href="addfile?path={$path-encoded}">add file</a>
            <form action="search" style="margin: 0px;padding:0px;float:right;"
                onSubmit="return onSearch(this.query.value);">
                <input type="hidden" name="path" value="{$path-encoded}" />
                <input style="margin: 0.1em;height: 1.4em;" class="browser-search" type="text"
                    name="query" placeholder="search..." />
            </form>
        </div>
    
    let $content := 
        <div class="browser">
            {
            $browser-header,
            $browser-content,
            $browser-footer
            }
        </div>

    return dbxdemo:render("Dropbox Demo", $content)

};

declare function dbxdemo:displayAsFile($path as xs:string,
                                       $is_deleted as xs:boolean){
    (: Extract the file name from the path :)
    let $filename := functx:substring-after-last($path, '/')

    let $deleted-class := if ($is_deleted) then
            " deleted"
        else
            ()
    
    let $path-encoded := dropbox:encode-path(fn:substring-after($path, '/'))
    
    return
        <div class="file{$deleted-class}">
            <div class="actions">
                <div>Actions</div>
                {
                if ($is_deleted) then
                    <ul>
                        <li><a href="restore?path={$path-encoded}">restore</a></li>
                    </ul>
                else
                    <ul>
                        <li><a href="copy?path={$path-encoded}">copy</a></li>
                        <li><a href="move?path={$path-encoded}">move</a></li>
                        <li><a href="delete?path={$path-encoded}">delete</a></li>
                        <li><a href="restore?path={$path-encoded}">restore</a></li>
                        <li><a href="content?path={$path-encoded}">download</a></li>
                    </ul>
                }
            </div>
            {
            if ($is_deleted) then
                <a class="file-link">
                    <div class="icon">{" "}</div>
                    <span class="">{$filename}</span>
                </a>
            else
                <a class="file-link" href="open?path={$path-encoded}">
                    <div class="icon">{" "}</div>
                    <span class="">{$filename}</span>
                </a>
            }
            
        </div>
};

declare function dbxdemo:displayAsFolder($path as xs:string,
                                         $is_deleted as xs:boolean)
{
    (: Extract the file name from the path :)
    let $filename := functx:substring-after-last($path, '/')
    
    let $deleted-class := if ($is_deleted) then
            " deleted"
        else
            ()
    
    let $path-encoded := dropbox:encode-path(fn:substring-after($path, '/'))
    
    return 
        <div class="folder{$deleted-class}">
            <div class="actions">
                <div>Actions</div>
                {
                if ($is_deleted) then
                    <ul>
                        <li>no actions</li>
                    </ul>
                else
                    <ul>
                        <li><a href="copy?path={$path-encoded}">copy</a></li>
                        <li><a href="move?path={$path-encoded}">move</a></li>
                        <li><a href="delete?path={$path-encoded}">delete</a></li>
                    </ul>
                }
            </div>
            {
            if ($is_deleted) then
                <a class="folder-link" href="browse?path={$path-encoded}">
                    <div class="icon">
                        <img src="/folder.png" />
                    </div>
                    <span class="">{$filename}</span>
                </a>
            else
                <a class="folder-link" href="browse?path={$path-encoded}">
                    <div class="icon">
                        <img src="/folder.png" />
                    </div>
                    <span class="">{$filename}</span>
                </a>
            }
        </div>
};



declare sequential function dbxdemo:delete() {
    (: Get the path parameter from the URL :)
    let $path := http:get-parameters("path", "")
    
    let $response := dropbox:delete("sandbox", $path, "de")
    
    let $dialog-header :=
        <div class="dialog-header">
            {dbxdemo:header-path($path, ($response/dbs:is_dir = fn:true()))}
        </div>
        
    let $dialog-content :=
        <div class="dialog-content" style="overflow: auto;">
            <span>{$response/dbs:path} has been deleted.</span>
        </div>

    let $parent-path-encoded := dropbox:encode-path(functx:substring-before-last($path, '/'))

    let $dialog-footer :=
        <div class="dialog-footer">
            <a class="dialog-cancel-button" href="browse?path={$parent-path-encoded}">close</a>
        </div>

    let $content := 
        <div class="dialog">
            {
            $dialog-header,
            $dialog-content,
            $dialog-footer
            }
        </div>
        
    let $title := fn:concat("Dropbox Demo - Delete '", $path, "'")
    
    return dbxdemo:render($title, $content)    
};

declare sequential function dbxdemo:move() {
    (: Get the path parameter from the URL :)
    let $path := http:get-parameters("path", "")
    let $to_path := http:get-parameters("to_path", "")
    
    let $meta := dropbox:metadata("sandbox", $path,(),(),(),fn:true(),(),())
    
    let $response := if ($to_path = "") then
            ()
        else
            dropbox:move("sandbox", $path, $to_path, "de")
    
    let $dialog-header :=
        <div class="dialog-header">
            {dbxdemo:header-path($path, ($meta/dbs:is_dir = fn:true()))}
        </div>
        
    let $dialog-content :=
        <div class="dialog-content" style="overflow: auto;">
            {
            if (fn:empty($response)) then
                <form class="dialog-form" action="move" method="POST">
                    <input type="hidden" name="path" value="{$path}" />
                    <div class="dialog-label">Move to:</div>
                    <input class="dialog-input" type="text" name="to_path" value="{$path}"/>
                </form>
            else
                <span>'{$path}' has been moved to '{$response/dbs:path/text()}'</span>
            }
        </div>

    let $parent-path-encoded := dropbox:encode-path(functx:substring-before-last($path, '/'))

    let $dialog-footer :=
        <div class="dialog-footer">
            {
            if (fn:empty($response)) then
                (
                <a class="dialog-cancel-button" href="browse?path={$parent-path-encoded}">cancel</a>
                ,
                <a class="dialog-submit-button" onClick="forms[0].submit()">move</a>
                )
            else
                <a class="dialog-cancel-button" href="browse?path={$parent-path-encoded}">close</a>
            }
        </div>

    let $content := 
        <div class="dialog">
            {
            $dialog-header,
            $dialog-content,
            $dialog-footer
            }
        </div>
        
    let $title := fn:concat("Dropbox Demo - Move '", $path, "'")
    
    return dbxdemo:render($title, $content)
};


declare sequential function dbxdemo:addfolder() {
    (: Get the path parameter from the URL :)
    let $path := http:get-parameters("path", "")
    let $folder_name := http:get-parameters("folder_name", "")
    
    let $response := if ($folder_name = "") then
            ()
        else
            dropbox:create_folder("sandbox", fn:concat($path, "/",$folder_name), "de")
    
    let $dialog-header :=
        <div class="dialog-header">
            {dbxdemo:header-path($path,fn:true())}
        </div>
        
    let $dialog-content :=
        <div class="dialog-content" style="overflow: auto;">
            {
            if (fn:empty($response)) then
                <form class="dialog-form" action="addfolder" method="POST">
                    <input type="hidden" name="path" value="{$path}" />
                    <div class="dialog-label">Name of new folder:</div>
                    <input class="dialog-input" type="text" name="folder_name" />
                </form>
            else
                <span>Folder '{$response/dbs:path/text()}' has been created.</span>
            }
        </div>

    let $path-encoded := dropbox:encode-path($path)

    let $dialog-footer :=
        <div class="dialog-footer">
            {
            if (fn:empty($response)) then
                (
                <a class="dialog-cancel-button" href="browse?path={$path-encoded}">cancel</a>
                ,
                <a class="dialog-submit-button" onClick="forms[0].submit()">add folder</a>
                )
            else
                <a class="dialog-cancel-button" href="browse?path={$path-encoded}">close</a>
            }
        </div>

    let $content := 
        <div class="dialog">
            {
            $dialog-header,
            $dialog-content,
            $dialog-footer
            }
        </div>
        
    let $title := fn:concat("Dropbox Demo - Add Folder to '", $path, "'")
    
    return dbxdemo:render($title, $content)
};


declare sequential function dbxdemo:copy() {
    (: Get the path parameter from the URL :)
    let $path := http:get-parameters("path", "")
    let $to_path := http:get-parameters("to_path", "")
    
    let $response := if ($to_path = "") then
            ()
        else
            dropbox:copy("sandbox", $path, $to_path, "de")
    
    let $dialog-header :=
        <div class="dialog-header">
            {dbxdemo:header-path($path,fn:false())}
        </div>
        
    let $dialog-content :=
        <div class="dialog-content" style="overflow: auto;">
            {
            if (fn:empty($response)) then
                <form class="dialog-form" action="copy" method="POST">
                    <input type="hidden" name="path" value="{$path}" />
                    <div class="dialog-label">Path of copy:</div>
                    <input class="dialog-input" type="text" name="to_path" value="{$path}_(Copy)"/>
                </form>
            else
                <span>File '{$path}' has been copied to '{$response/dbs:path/text()}'</span>
            }
        </div>

    let $parent-path-encoded := dropbox:encode-path(functx:substring-before-last($path, '/'))

    let $dialog-footer :=
        <div class="dialog-footer">
            {
            if (fn:empty($response)) then
                (
                <a class="dialog-cancel-button" href="browse?path={$parent-path-encoded}">cancel</a>
                ,
                <a class="dialog-submit-button" onClick="forms[0].submit()">copy</a>
                )
            else
                <a class="dialog-cancel-button" href="browse?path={$parent-path-encoded}">close</a>
            }
        </div>

    let $content := 
        <div class="dialog">
            {
            $dialog-header,
            $dialog-content,
            $dialog-footer
            }
        </div>
        
    let $title := fn:concat("Dropbox Demo - Copy '", $path, "'")
    
    return dbxdemo:render($title, $content)
};



declare sequential function dbxdemo:open() {
    (: get the path from the http request :)
    let $path := http:get-parameters("path", "")
    let $path-encoded := dropbox:encode-path($path)

    let $meta := dropbox:metadata("sandbox", $path,(),(),(),fn:true(),(),())
    let $content-type := $meta/dbs:mime_type/text()

    let $response := 
        if (fn:contains($content-type, "image")) then
            ()
        else
            dropbox:files("sandbox", $path, ())
        
    let $dialog-header :=
        <div class="dialog-header">
            {dbxdemo:header-path($path,fn:false())}
        </div>
        
    let $dialog-content :=
        <div class="dialog-content" style="overflow: auto;">
            {
            if (fn:contains($content-type, "image")) then
                <img style="width: 100%;" src="content?path={$path-encoded}"></img>
            else
                <textarea style="width: 100%; height: 20em;">{$response/oas:payload/text()}</textarea>
            }
        </div>

    let $parent-path-encoded := dropbox:encode-path(functx:substring-before-last($path, '/'))

    let $dialog-footer :=
        <div class="dialog-footer">
            <a class="dialog-cancel-button" href="browse?path={$parent-path-encoded}">close</a>
        </div>

    let $content := 
        <div class="dialog">
            {
            $dialog-header,
            $dialog-content,
            $dialog-footer
            }
        </div>
        
    let $title := fn:concat("Dropbox Demo - File ", $path)
    
    return dbxdemo:render($title, $content)
};

declare function dbxdemo:header-path($path as xs:string, $is_dir as xs:boolean) {
    let $folder-path  :=
        if ($is_dir = fn:true()) then
            $path
        else
            if (fn:contains($path, "/")) then
                functx:substring-before-last-match($path, "/")
            else
                ""

    let $path-elems := fn:tokenize($folder-path,"/")
    
    let $path-links :=
        for $elem-number in (1 to fn:count($path-elems))
            let $full-path := 
                for $i in (1 to $elem-number)
                    return $path-elems[$i]
            return
                <path-link>
                    <path>{dropbox:encode-path(fn:string-join($full-path, '/'))}</path>
                    <label>{$path-elems[$elem-number]}</label>
                </path-link>
    
    return (    
        <a class="folder-path"  href="browse?path=">/</a>
        ,
        for $path-link in $path-links
            return <a class="folder-path" href="browse?path={$path-link/path}">{$path-link/label}/</a>
        ,
        if ($is_dir) then
            ()
        else
            <a class="folder-path">{dropbox:encode-path(functx:substring-after-last-match($path, "/"))}</a>
        )
};

declare sequential function dbxdemo:restore() {
    (: Get the path parameter from the URL :)
    let $path := http:get-parameters("path", "")
    let $revision := http:get-parameters("rev", "")
    let $path-encoded := dropbox:encode-path($path)
    
    let $response :=
        if ($revision = "") then
            dropbox:revisions("sandbox", $path, (), "de")
        else
            dropbox:restore("sandbox", $path, $revision, "de")
            
    let $is_dir :=
        if ($revision = "") then
            $response[0]/dbs:is_dir = fn:true()
        else
            $response/dbs:is_dir = fn:true()
    
    let $dialog-header :=
        <div class="dialog-header">
            {dbxdemo:header-path($path, $is_dir)}
        </div>
        
    let $dialog-content :=
        if ($revision = "") then
            <div class="browser-content" style="overflow: auto;">
            {
                for $rev in $response/dbs:metadata
                    let $url := fn:concat("restore?path=", $path-encoded, "&amp;rev=", $rev/dbs:rev/text())
                    return
                        <div class="revision">
                            <a href="{$url}">Revision '{$rev/dbs:rev/text()}' from {$rev/dbs:modified/text()}</a>
                        </div>
            }
            </div>
        else
            <div class="dialog-content" style="overflow: auto;">
                <span>{$response/dbs:path} has been restored to revision '{$response/dbs:rev}'.</span>
            </div>
    
    let $parent-path-encoded := dropbox:encode-path(functx:substring-before-last($path, '/'))

    let $dialog-footer :=
        <div class="dialog-footer">
            <a class="dialog-cancel-button" href="browse?path={$parent-path-encoded}">close</a>
        </div>

    let $content := 
        <div class="dialog">
            {
            $dialog-header,
            $dialog-content,
            $dialog-footer
            }
        </div>
        
    let $title := fn:concat("Dropbox Demo - Move '", $path, "'")
    
    return dbxdemo:render($title, $content)    
};

declare sequential function dbxdemo:content() {
    (: get the path from the http request :)
    let $path := http:get-parameters("path", "")

    let $response := dropbox:files("sandbox", $path, ())
    
    (: Set the http headers that were received in the response :)
    let $a :=
        for $header in $response/oas:headers/oas:header
            return http:set-header($header/@name, $header/text())
    
    return try {
            zorba-base64:decode($response/oas:payload/text())
        } catch * {
            $response/oas:payload/text()
        }
(:
    return
        if ($response/oas:headers/oas:header[@name="Content-Encoding"]/text() = "gzip") then
            $response/oas:payload/text()
        else
            zorba-base64:decode($response/oas:payload/text())
:)
};

declare sequential function dbxdemo:search() {
    (: get the path from the http request :)
    let $path := http:get-parameters("path", "")
    let $query := http:get-parameters("query", "")
    let $path-encoded := dropbox:encode-path($path)
    
    (: get metadata for path :)
    let $metadata_path := ()
    
    let $response := dropbox:search($query, "sandbox", $path, (), fn:true(), ())
    
    let $browser-header :=
        <div class="browser-header">
            <span>Search for '{$query}' in '/{$path}'</span>
        </div>
    
    let $browser-content := 
        if ($response/dbs:metadata) then
            for $item in $response/dbs:metadata
                return if ($item/dbs:is_dir = fn:true()) then
                    dbxdemo:displayAsFolder($item/dbs:path, ($item/dbs:is_deleted = fn:true()))
                else
                    dbxdemo:displayAsFile($item/dbs:path, ($item/dbs:is_deleted = fn:true()))
        else
            ()
    
    let $browser-footer :=
        <div class="browser-footer">
            <a class="browser-action" href="browse?path={$path-encoded}">back</a>
        </div>
    
    let $content := 
        <div class="browser">
            {
            $browser-header,
            $browser-content,
            $browser-footer
            }
        </div>

    return dbxdemo:render("Dropbox Demo - Search Results", $content)

};


declare sequential function dbxdemo:addfile() {
    (: Get the path parameter from the URL :)
    let $path := http:get-parameters("path", "")
    let $path-encoded := dropbox:encode-path($path)

    let $file-contents :=
        if (fn:count(http:get-file-names()) > 0) then
            try {
                zorba-base64:decode(http:get-files(http:get-file-names()))
                (:http:get-files(http:get-file-names()):)
            } catch * {
                http:get-files(http:get-file-names())
            }
        else
            ()
    
    let $upload-path :=
        if (fn:empty($file-contents)) then
            ()
        else
            fn:concat($path, "/", http:get-content-file-names(http:get-file-names()))
    
    let $response := if (fn:empty($file-contents)) then
            ()
        else
            dropbox:files_put("sandbox", $file-contents, $upload-path, "de", (), ())

    let $dialog-header :=
        <div class="dialog-header">
            {dbxdemo:header-path($path,fn:true())}
        </div>
        
    let $dialog-content :=
        <div class="dialog-content" style="overflow: auto;">
            {
            if (fn:empty($response)) then
                <form class="dialog-form" action="addfile" method="POST"
                 enctype="multipart/form-data">
                    <input type="hidden" name="path" value="{$path}" />
                    <div class="dialog-label">File:</div>
                    <input class="dialog-file" type="file" name="uploadfile" />
                </form>
            else
                <span>File '{$response/dbs:path/text()}' has been added.</span>
            }
        </div>

    let $dialog-footer :=
        <div class="dialog-footer">
            {
            if (fn:empty($response)) then
                (
                <a class="dialog-cancel-button" href="browse?path={$path-encoded}">cancel</a>
                ,
                <a class="dialog-submit-button" onClick="forms[0].submit()">add</a>
                )
            else
                <a class="dialog-cancel-button" href="browse?path={$path-encoded}">close</a>
            }
        </div>

    let $content := 
        <div class="dialog">
            {
            $dialog-header,
            $dialog-content,
            $dialog-footer
            }
        </div>
        
    let $title := "Dropbox Demo - Add File"
    
    return dbxdemo:render($title, $content)
};