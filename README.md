[![Community Plus header](https://github.com/newrelic/opensource-website/raw/master/src/images/categories/Community_Plus.png)](https://opensource.newrelic.com/oss-category/#community-plus)

# New Relic OCI Integrations

This repository contains integrations to forward metrics and logs from Oracle Cloud Infrastructure (OCI).

## Prerequisites

* [New Relic Ingest Key & API Key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#license-key)
* OCI user with Cloud Administrator role to create resources/stacks

## Installation

For convenience, Terraform configurations are supplied to create OCI Resource Manager (ORM) stacks. Each sub-section below outlines pre-requisites, steps, and resulting resources created for either metrics or logs ingestion.

#### NR-OCI Stack Deployment

A single `.zip` file is now available to deploy all required stacks (Policy, Metrics, and Logs). This simplifies the process by combining all configurations into one deployment package.

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/newrelic/newrelic-oracle-cloud-integration/releases/latest/download/newrelic-oci-terrform.zip)

To create the unified stack in the OCI Portal:

1. Download the latest newrelic-oci-terraform.zip release in this repo.
2. Navigate to _Resource Manager -> Stacks_.
3. Select *Create stack*.
4. Under *Stack configuration*, select `Browse`.
5. Select the entire `unified stack` directory & *Upload*.
6. Optionally modify the name, description, compartment, and tags. Leave the option to use custom Terraform providers *unchecked*. Select *Next*.
7. Provide the required configuration inputs for Configuration, Policy, Metrics, and Logs as outlined below.

##### Stack Configuration

| Input                        | Type         | Required | Description
|------------------------------|--------------| -------- | -----------
| New Relic Dynamic Group      | string       | TRUE | Name of the dynamic group to be created.
| New Relic Policy             | string       | TRUE | Name of the policy to be created.
| New Relic Function App Name  | string       | TRUE | Name of the function application to be created.
| New Relic Connector Hub Name | string       | TRUE | Name of the connector hub to be created.
| Metric Namespaces            | List(String) | TRUE | Name of the metrics namespaces to be forwarded to New Relic.

##### Metrics Configuration

| Input                     | Type | Required | Description
|---------------------------| ---- | -------- | -----------
| New Relic Metric Endpoint | enum | TRUE | New Relic endpoint to forward metrics to. Either US or EU endpoint.
| New Relic Ingest Key      | string | TRUE | New Relic Ingest Key used to forward metrics.
| New Relic API Key         | string | TRUE | New Relic API Key used to Link OCI Account to New Relic.


##### Logs Configuration

| Input | Type | Required | Description
| ----- | ---- | -------- | -----------
| Log Group OCID | string | TRUE | The OCID of the Log Group containing the logs to be forwarded.
| Log OCID | string | TRUE | The OCID of the Log file to be forwarded.

8. Once all required configuration is input, select *Next*.
9. Review inputs, and select `Create` to create the stack. Check *Run apply* to create resources immediately.

After the stack is created, resources for Policy, Metrics, and Logs will be available and configured successfully.

#### Policy Stack

An ORM policy stack must be created in the home region of the tenancy. The policy stack creates:

* A dynamic group with rule `All {resource.type = 'serviceconnector'}`, which enables access to the connector hub
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

### Logs

The Logs stack creates the following resources:

* A VCN that routes traffic to New Relic (alternatively, use an existing VCN)
* Application that contains a function
* Function Application that contains the `logs-function` to forward logs. The Docker image is deployed to or pulled from the Container Registry.
* Service Connector that routes logs to the Function Application

#### Prerequisites
* A Log Group containing a custom log or service log

To create a Logging group:

1. In the OCI portal, navigate to _Logging -> Log Groups_.
2. Select your compartment and click *Create Log Group*. A side panel opens.
3. Enter a descriptive name (i.e - `newrelic_log_group`), and optionally provide a description and tags.
4. Click *Create* to set up your new Log Group.
5. Under *Resources*, select *Logs*.
6. Click to *Create custom log* or *Enable service log* as desired.
7. Click *Enable Log*, to create your new OCI Log.

For more information on OCI Logs, see [Enabling Logging for a Resource](https://docs.oracle.com/en-us/iaas/Content/Logging/Task/enabling_logging.htm).

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
| ----- | ---- | -------- | -----------
| NR_METRIC_ENDPOINT | string | TRUE | The metric api endpoint to forward metrics to (EU or US). Default: `metric-api.newrelic.com`
| FORWARD_TO_NR | string | False | Toggle forwarding to New Relic - Can be one of: `True,False`. Default: `True`
| LOGGING_ENABLED | string | FALSE | The logging level for function logs emitted - Can be one of: `INFO,WARNING,ERROR,DEBUG`. Default: `INFO`
| TENANCY_OCID | string | TRUE | The OCID of the tenancy to which the metrics are being forwarded.
|SECRET_OCID | string | TRUE | The OCID of the secret containing the New Relic Ingest Key.
|VAULT_REGION | string | TRUE | The region of the vault containing the secret with the New Relic Ingest Key.


## Contributing

We encourage your contributions to improve newrelic-oracle-cloud-integration! Keep in mind when you submit your pull request, you'll need to sign the CLA via the click-through using CLA-Assistant. You only have to sign the CLA one time per project. If you have any questions, or to execute our corporate CLA, required if your contribution is on behalf of a company, please drop us an email at opensource@newrelic.com.

**A note about vulnerabilities**

As noted in our [security policy](../../security/policy), New Relic is committed to the privacy and security of our customers and their data. We believe that providing coordinated disclosure by security researchers and engaging with the security community are important means to achieve our security goals.

If you believe you have found a security vulnerability in this project or any of New Relic's products or websites, we welcome and greatly appreciate you reporting it to New Relic through [HackerOne](https://hackerone.com/newrelic).

## License

newrelic-oracle-cloud-integration is licensed under the [Apache 2.0](http://apache.org/licenses/LICENSE-2.0.txt) License.
