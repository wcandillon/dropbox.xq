(:
 : Copyright 2010 28msec Inc.
 :)

module namespace err = "http://www.28msec.com/templates/oauth/lib/error";

import module namespace http="http://www.28msec.com/modules/http";

declare function err:show($status, $msg)
{
  <html>
      <head>
          <title> { $status } - because an error happended!</title>
      </head>
    <body>
      <center><h1 style="color: #FF0000">...because an error happened!</h1>
        <table width="70%">
          {
            if ( $status eq 404 ) then (
              <tr height="50"><td colspan="2">The requested URL was not found on this server ({ $status }).</td></tr>,
              <tr><td valign="top"><b>Reason:</b></td><td> { $msg }</td></tr>,
              <tr height="50"><td colspan="2">If you were trying to access the project's default handler visit <a href="/default/index">/default/index</a>. If you think this is an error, please contact <a href="mailto:support@28msec.com">support@28msec.com</a>.</td></tr>
            )
            else (
              <tr valign="top" height="50"><td><b>Status:</b></td><td>{ $status }</td></tr>,
              <tr valign="top"><td><b>Message:</b></td><td>{ $msg }</td></tr>
            )
          }
        </table>
      </center>
      <p>
        <hr/>
        <h1> Request Information: </h1>
        <table>
          <tr>
            <td>Request Method: </td><td>{ http:get-method() }</td>
          </tr>
          <tr>
            <td>Content-Type:</td><td>{ http:get-content-type() }</td>
          </tr>
          <tr>
            <td>Remote Port:</td><td>{ http:get-remote-port() }</td>
          </tr>
          <tr>
            <td>Query String:</td><td>{ http:get-query-string() }</td>
          </tr>
          <tr>
            <td>User Agent:</td><td>{ http:get-user-agent() }</td>
          </tr>
          <tr>
            <td>HTTP Accept Header:</td><td>{ http:get-header("HTTP_ACCEPT") }</td>
          </tr>
          <tr>
            <td width="200">All Header Names</td><td>{ http:get-header-names() }</td>
          </tr>
          {
          let $params := http:get-parameter-names()
          return
            if (fn:exists($params)) then
              <tr>
                <td valign="top">Request Parameters:</td>
                <td>
                  <table border="0">
                    <tr><td><b>Name</b></td><td><b>Value</b></td></tr>
                    {
                        for $param in $params
                        let $values := http:get-parameters($param)
                        for $value in $values
                        return 
                          <tr>
                            <td>{$param}</td>
                            <td>{$value}</td>
                          </tr>
                    }
                  </table>
                </td>
              </tr>
            else (),
          
          let $cookies := http:get-cookies()
          return
            if (fn:exists($cookies)) then
              <tr>
                <td valign="top">Cookies:</td>
                <td>
                  <table border="0">
                    <tr><td><b>Name</b></td><td><b>Value</b></td></tr>
                    {
                      for $cookie in $cookies
                      return 
                        <tr>
                          <td>{$cookie/data(@name)}</td>
                          <td>{$cookie/child::node()}</td>
                        </tr>
                    }
                  </table>
                </td>
              </tr>
            else ()
          }
        </table>
        <hr/>
      </p>
    </body>
  </html>
};


