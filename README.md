## HelloID-Conn-Prov-Source-RAET-IAM-API-HR-Core-Business

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |
<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/vismayouserve-logo.png" width="500">
</p>

## Versioning
| Version | Description | Date |
| - | - | - |
| 1.1.2   | Updated logging and handling for too many request errors | 2022/09/28  |
| 1.1.1   | Changed to use employees (instead of persons) endpoint as the extension fields are only avaible on the employees endpoint | 2022/08/19  |
| 1.1.0   | Added support for mutliple contracts | 2022/07/12  |
| 1.0.0   | Initial release | 2021/04/23  |

## Table of contents
- [HelloID-Conn-Prov-Source-RAET-IAM-API-HR-Core-Business](#helloid-conn-prov-source-raet-iam-api-hr-core-business)
- [Versioning](#versioning)
- [Table of contents](#table-of-contents)
- [Introduction](#introduction)
- [Endpoints implemented](#endpoints-implemented)
- [Raet IAM API status monitoring](#raet-iam-api-status-monitoring)
- [Differences between RAET versions](#differences-between-raet-versions)
      - [HR Core Business](#hr-core-business)
- [Raet IAM API documentation](#raet-iam-api-documentation)
- [Getting started](#getting-started)
  - [Connection settings](#connection-settings)
  - [Prerequisites](#prerequisites)
  - [Remarks](#remarks)
  - [Mappings](#mappings)
  - [Scope](#scope)
- [Getting help](#getting-help)
- [HelloID docs](#helloid-docs)

---

## Introduction

This connector retrieves HR data from the RAET IAM API. Please be aware that there are several versions. This version connects to the latest API release and is intended for **HR Core Business** Customers. The code structure is mainly the same as the HR Beaufort variant. Despite the differences below.


## Endpoints implemented

- /employees (employees)
- /companies (companies)
- /organizationUnits (departments)
- /valueList/costCenter (costcenters)
- /valueList/classification (classifications)
- /jobProfiles (professions)

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
- Assignments not available in HR Core Business 


## Raet IAM API documentation
Please see the following website about the Raet IAM API documentation. Also note that not all HR fields are available depending on the used HR Core by your customer; HR Core Beaufort or HR Core Business. For example; company and costcenter are not available for HR Core Beaufort customers.
- [Knowledge base YouServe API's](https://community.visma.com/t5/Knowledge-base-YouServe-API-s/tkb-p/nl_ys_YouServe_API_knowledge_base/label-name/IAM%20API)
- [IAM API - Endpoints](https://community.visma.com/t5/Knowledge-base-YouServe-API-s/IAM-API-Endpoints/ta-p/472228#toc-hId-980280917)
- [IAM API - Domain model and concepts](https://community.visma.com/t5/Knowledge-base-YouServe-API-s/IAM-API-Domain-model-and-concepts/ta-p/472255)
- [Swagger Youserve IAM API](https://youserve-domain-api.github.io/SwaggerUI/iamapi.html)
- [Youserve Developer portal](https://developers.youserve.nl/)


---

## Getting started
### Connection settings
The following settings are required to run the source import.

| Setting                                       | Description                                                               | Mandatory   |
| --------------------------------------------- | ------------------------------------------------------------------------- | ----------- |
| Client ID                                     | The Client ID to connect to the Raet IAM API.                             | Yes         |
| Client Secret                                 | The Client Secret to connect to the Raet IAM API.                         | Yes         |
| Tenant ID                                     | The Tenant ID to specify to which tenant to connect to the Raet IAM API.  | Yes         |
| Exclude persons without contracts in HelloID  | Exclude persons without contracts in HelloID yes/no.                      | No          |

### Prerequisites
 - Authorized Raet Developers account in order to request and receive the API credentials. See: https://developers.youforce.com. Make sure your client does the IAM API access request themselves on behalf of your own Raet Developers account (don't use Tools4ever, but your own developer account). More info about Raet Developers Portal: https://youtu.be/M9RHvm_KMh0
- ClientID, ClientSecret and tenantID to authenticate with RAET IAM-API Webservice

### Remarks
 - Currently, there is no support for Assignments for HR Core Business

### Mappings
A basic mapping is provided. Make sure to further customize these accordingly.
Please choose the default mappingset to use with the configured configuration.

### Scope
The data collection retrieved by the queries is a default set which is sufficient for HelloID to provision persons.
The queries can be changed by the customer itself to meet their requirements.

## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
