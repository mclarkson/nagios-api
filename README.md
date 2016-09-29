nagios-api is a collective group of tools I use at my company for nagios registering of AWS clients in the cloud.

This is used in conjunction with: http://nagrestconf.smorg.co.uk

* COMPANY / company should be changed to your company.

* Tweaks should be made to fit your environment!

###############################################################

There are two parts of this all done via ansible role playbooks

ansible/nagios - configure nagios CentOS 7 box with NagiosConfApi

ansible/base_nagios_register - Setup a SystemD CentOS7 register/deregister service for hosts

###############################################################

Future work to be done

* ServiceGroups don't currently work, I need to think about how to poll/sort the members 
