[![Community Plus header](https://github.com/newrelic/opensource-website/raw/master/src/images/categories/Community_Plus.png)](https://opensource.newrelic.com/oss-category/#community-plus)

# New Relic OCI Integrations

This repository contains integrations to forward metrics and logs from Oracle Cloud Infrastructure (OCI).

## Prerequisites

* [New Relic Ingest Key & API Key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#license-key)
* OCI user with Cloud Administrator role to create resources/stacks

## Installation

For convenience, Terraform configurations are supplied to create OCI Resource Manager (ORM) stacks. Each sub-section below outlines pre-requisites, steps, and resulting resources created for either metrics or logs ingestion.

#### NR-OCI Stack Deployment

Terraform configurations are provided for easy deployment using OCI Resource Manager (ORM). The setup is divided into two scripts:

1. Policy Setup: Creates the required dynamic group and policy in your home region.

2. Metrics Setup: Deploys the function, service connector, and supporting resources to forward metrics.

#### Policy Stack

An ORM policy stack must be created in the home region of the tenancy. The policy stack creates:

* A dynamic group with rule `ANY {resource.type = 'serviceconnector', resource.type = 'fnfunc'}`, which enables access to the connector hub and function resources.
* A policy in the root compartment to allow connector hubs to read metrics and invoke functions. The following statements are added to the policy:

```
Allow dynamic-group <GROUP_NAME> to read metrics in tenancy
Allow dynamic-group <GROUP_NAME> to use fn-function in tenancy
Allow dynamic-group <GROUP_NAME> to use fn-invocation in tenancy
Allow dynamic-group <GROUP_NAME> to manage stream-family in tenancy
Allow dynamic-group <GROUP_NAME> to manage repos in tenancy
Allow dynamic-group <GROUP_NAME> to read secret-bundles in tenancy
```

#### Metrics Stack

After the policy stack is successfully created,the Metrics stack will be created, which creates the following resources:

* A VCN that routes traffic to New Relic (alternatively, use an existing VCN)
* Application that contains a function
* Function Application that contains the `metrics-function` to forward metrics. The Docker image is deployed to or pulled from the Container Registry.
* Service Connector that routes metrics to the Function Application


Once the stack is created, metrics should be available in the New Relic portal. Open the query builder and run the following query to validate:
```
FROM Metric SELECT * where metricName like '%oci%'
```

### Service Connector

Initially, the connector is created with default metric namespaces to collect metrics for. This can be configured by following the steps below:

1. In the OCI Portal, under `Connectors`, select the newrelic metrics connector
2. Select Edit
3. Under `Configure Source -> Namespaces`, select or deselect specific namespaces of interest to collect metrics on.

For details on specific metric namespaces and what metrics reside under each namespace, check Oracle's docs for a specific service/namespace. Examples:

* [Compute](https://docs.oracle.com/en-us/iaas/Content/Compute/References/computemetrics.htm#Availabl)
* [Database](https://docs.oracle.com/en/cloud/paas/base-database/available-metrics/index.html#articletitle)

### Metrics Function

The following table lists available environment variables that can be set for the function:

| Input | Type | Required | Description
| ----- | ---- |----------| -----------
| NR_METRIC_ENDPOINT | string | TRUE     | The metric api endpoint to forward metrics to (EU or US). Default: `newrelic-metric-api`
| FORWARD_TO_NR | string | FALSE    | Toggle forwarding to New Relic - Can be one of: `True,False`. Default: `True`
| LOGGING_ENABLED | string | FALSE    | The logging level for function logs emitted - Can be one of: `INFO,WARNING,ERROR,DEBUG`. Default: `INFO`
| TENANCY_OCID | string | TRUE     | The OCID of the tenancy to which the metrics are being forwarded.
|SECRET_OCID | string | TRUE     | The OCID of the secret containing the New Relic Ingest Key.
|VAULT_REGION | string | TRUE     | The region of the vault containing the secret with the New Relic Ingest Key.


## Contributing

We encourage your contributions to improve newrelic-oracle-cloud-integration! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project. If you have any questions, or to execute our corporate CLA, required if your contribution is on behalf of a company, please drop us an email at opensource@newrelic.com.

**A note about vulnerabilities**

As noted in our [security policy](../../security/policy), New Relic is committed to the privacy and security of our customers and their data. We believe that providing coordinated disclosure by security researchers and engaging with the security community are important means to achieve our security goals.

If you believe you have found a security vulnerability in this project or any of New Relic's products or websites, we welcome and greatly appreciate you reporting it to New Relic through [HackerOne](https://hackerone.com/newrelic).

## License

newrelic-oracle-cloud-integration is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.
