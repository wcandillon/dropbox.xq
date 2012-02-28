module namespace def = "http://www.28msec.com/templates/oauth/default";

import module namespace http="http://www.28msec.com/modules/http";

declare sequential function def:index ()
{
  http:set-content-type("text/html");
  <html>
    <head>
      <title>Dropbox API Demo</title>
    </head>
    <body>
      <p>
	Welcome to the Dropbox API Demo! This is just a small application which uses our newly developed XQuery Dropbox module, offering the full functionality 
	of the <a href="https://www.dropbox.com/developers/reference/api">Dropbox REST API</a>.</p>
	<p>	If you don't have access to the Dropbox test account linked with this application, use the following credentials:</p>
  <ul>
    <li><b>Login:</b>&#160;william.candillon@28msec.com</li>
    <li><b>Password:</b>&#160;foobar</li>
  </ul>
	<p>Otherwise, go ahead and <a href="/dbxdemo/start">start the Demo!</a></p>
	    </body>
  </html>;

};


