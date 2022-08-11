# splunk-yum-repo
Allows for one-step creation of an automatically updated local yum/dnf RPM repository for splunk-enterprise and splunk-universal-fowarder RPM packages, allowing these packages to be kept up to date in your environment without having to check and download from splunk.com each time. 

This repository contains scripts/cronjobs/repo-definitions to perform nightly downloads of splunk-universal-forwarder and splunk-enterprise packages and create/host a YUM repository.

This basically lets you create a local Splunk YUM repo of the two main splunk RPM packages available from splunk.com.

Specifically, this creates a nightly-updating Splunk repo for:
1. splunk-enterprise - this is the splunk package that installs the main splunk enteprise software
2. splunk-universal-forwarder - this is the splunk package that installs the splunk universal forwarder software

This makes it possible to manage Splunk installs using YUM/dnf, rather than having to manually download an RPM from splunk.com each time just to apply an update.

