
Nagios to ServiceNow Integration 

Overview: 

This script is setup to run as command and trigger on a Event Handler.  No use of database is required but could be modified to use one.
 

Script use REST API to talk to ServiceNow in order to create a new ticket or update a new ticket.  Script will be set to a event handler on each service which should execute when it is in a SOFT problem state, intially goes into a HARD problem state, or initially recovers form a SOFT or HARD state. 

Logging setting will be set to ERROR and will be written to /var/log/nagios/ServiceNowRest.log. 

Ticket will be created intially if no ticket is found.  Ticket is found based on a query of the short descirption string, if it is active and if it was created in the last 24 hours.  This query can be modified to fit your needs.

Script will also attempt to find the host in the Configuration Items based on the Hostname and Hostip.  If not found will just return a empty string and not set in the ticket.

Here are some links as well that talk about the ServiceNow rest API and Nagios command and event handling. 


http://wiki.servicenow.com/index.php?title=REST_API#gsc.tab=0 

https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/macrolist.html 

https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/eventhandlers.html 

 

Installation: 

 

Following perl modules are required to be installed before using this script.  Installing these will vary on OS/Distro but should be able to use the repo's or CPAN to do this. 

REST::Client 

JSON 

Config::Properties; 

Log::Log4perl 

The nagiosToServiceNow.pl,snNagios.properties and log4perl.conf file should go under /usr/local/nagios/libexec.  The snNagios.properties can really go anywhere but the nagiosToServiceNow.pl will need the $path variable updated with the new path.  Currently it is expecting for the perl script and properties file in the same path. 

Setup: 

You will create a command in Nagios to point to the script and pass the following variables: $HOSTNAME$, $HOSTIP$, $SERVICEDESC$, $SERVICEDESC$,$SERVICESTATE$,$SERVICEDURATION$, $SERVICEOUTPUT$ 

You will then need to setup an event handler for the given service check to trigger this command when the service changes state.  

Updating files: 

 

In theory only the snNagios.properties file should need to be updated.  It is setup in away where queries  can be writing and replaced in the snNagios.properties file.  Any type of custom variables or new functionality might require code updates to the nagiostoServiceNow.pl file. 

 

Here are a list of variables that a currently being putting into the replace hash map and are being search and replaced in the properties file: 

    <hostname>   - This variable is being passed by nagios $HOSTNAME$ 

    <hostip> - This variable is being passed by nagios $HOSTIP$ 

    <commandname>  - This variable is being passed by nagios $SERVICEDESC$ 

    <currentstate>  - This variable is being passed by nagios $SERVICESTATE$ 

    <timeinstate>  - This variable is being passed by nagios $SERVICEDURATION$ 

    <hostoutput>  - This variable is being passed by nagios $SERVICEOUTPUT$ 

    <update_state> - This is being calculated based on the current state. 

    <date>  - This is the day 24 hours before the current day 

    <time>  - this is the time 24 hours before the current time 

 

Troubleshooting: 

 

By default the log4perl.conf level will be set to ERROR.  If any type of checking or additional logging is required the level should be set to DEBUG.  The line will look like this below: 

 

log4perl.rootLogger              = DEBUG, snREST 

 

In additional you can turn on REST debugging in ServiceNow and check the corresponding logs.  It is important to remember that in ServiceNow the account logging in, needs to have the rest_service role and corresponding ACL's set on the tables. 
