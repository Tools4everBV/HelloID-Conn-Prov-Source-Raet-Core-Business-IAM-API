## HelloID-Conn-Prov-Source-RAET-IAM-API-HR-Core-Business

## Table of contents
- [Introduction](#Introduction)
- [Endpoints implemented](#Endpoints-implemented)
- [Raet IAM API status monitoring](#Raet-IAM-API-status-monitoring)
- [Differences between RAET versions](#Differences-RAET-between-versions)
- [Getting started](#Getting-started)
  + [Prerequisites](#Prerequisites)
  + [Configuration Settings](#Configuration-Settings)
  
---

## Introduction

This connector retrieves HR data from the RAET IAM API. Please be aware that there are several versions. This version connects to the latest API release and is intended for **HR Core Business** Customers. The code structure is mainly the same as the HR Beaufort variant. Despite the differences below.


## Endpoints implemented

- /employees  (person)
- /jobProfiles (person)
- /organizationUnits (departments)
- /roleAssignments (departments)

## Raet IAM API status monitoring
https://developers.youforce.com/api-status

## Differences between RAET versions
|  Differences | ManagerId  |  Person | nameAssembleOrder  | Assignments |
|---|---|---|---|---|
| HR Core Business:   |OrganizationUnits      |  A PersonObject foreach employement    |  Digits (0,1,2,3,4,)     | Not Supported  |
| HR Beaufort  | RoleAssignment        | One PersonObject with multiple Employments  | Letters((E,P,C,B,D)     | Available  |


##### HR Core Business
- Manager in OrganizationUnits endpoint (PersonID)
- Employee record for each employment
  - Must be sorted on newest record pick that one as Person (Identity)
  - Add All employments -or assignments to this person object (Unique)
 - nameAssembleOrder   Digits (0,1,2,3,4,)
 - All employee/employment data can be retrieved from the employee's endpoint
 - Assignments not available in HR Core Business 


## Raet IAM API documentation
Please see the following website about the Raet IAM API documentation. Also note that not all HR fields are available depending on the used HR Core by your customer; HR Core Beaufort or HR Core Business. For example; company and costcenter are not available for HR Core Beaufort customers.
- https://community.raet.com/developers-community/w/iam-api
- https://community.raet.com/developers-community/w/iam-api/2472/data-mapping

---

## Getting started
Please note that you need to have an authorized Raet Developers account in order to request and receive the API credentials. See: https://developers.youforce.com

Make sure your client does the IAM API access request themselves on behalf of your own Raet Developers account (don't use Tools4ever, but your own developer account)

More info about Raet Developers Portal: https://youtu.be/M9RHvm_KMh0

### Prerequisites
 - [ ] ClientID, ClientSecret and tenantID to authenticate with RAET IAM-API Webservice


### Configuration Settings
Use the configuration.json in the Source Connector on "Custom connector configuration". You can use the created field on the Configuration Tab to set the ClientID, ClienSecret and tenantID. Also you can choose if you want to include the assignments from the IAM-API.

![config](https://user-images.githubusercontent.com/67468224/110907438-ad492e80-830d-11eb-9507-7b7a61fe2b0d.jpg)

> **_NOTE:_**  Assignements is at the moment of writing not supported for HR Core Business

Please choose the default mappingset to use with the configured IAM-API configuration.

For employments:
personMapping_employments.json
contractMapping_employments.json

# HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/
