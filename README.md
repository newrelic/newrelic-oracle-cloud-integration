[![Community Plus header](https://github.com/newrelic/opensource-website/raw/master/src/images/categories/Community_Plus.png)](https://opensource.newrelic.com/oss-category/#community-plus)

# New Relic OCI Integrations

This repository contains integrations to forward metrics from Oracle Cloud Infrastructure (OCI).

## Prerequisites

* [OCI Auth Integration](https://docs-preview.newrelic.com/docs/oracle-cloud-infrastructure#wif) 
* [New Relic Ingest Key & API Key](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#license-key)
* OCI user with Cloud Administrator role to create resources/stacks

## Trust type: UPST or RPST

New Relic supports two WIF trust types for OCI. Pick one before deploying the ORM stack.

| Trust type | When to use | Setup docs |
|------------|-------------|------------|
| **UPST** (default) | Most customers. WIF impersonates a dedicated service user. Simplest path. | [UPST setup](https://docs-preview.newrelic.com/docs/oracle-cloud-infrastructure#upst-setup) |
| **RPST** | Multi-account customers, customers hitting OCI's IAM policy-statement limit, or anyone who wants claim-based / tag-based authorization. | [RPST setup](https://docs-preview.newrelic.com/docs/oracle-cloud-infrastructure#rpst-setup) |

The `trust_type` variable in the Policy Stack (below) defaults to `UPST`. Set it to `RPST` inside the OCI Resource Manager form if your identity-propagation trust was created with `subjectType: Resource`. If you also want tag-based scoping via `ext_resource_tag`, use the [terraform provider](https://registry.terraform.io/providers/newrelic/newrelic/latest/docs/resources/cloud_oci_link_account) — the ORM stack does not currently expose `resource_tag`.

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
Allow dynamic-group <GROUP_NAME> to read secret-bundles in tenancy
```

#### Metrics Stack

After the policy stack is successfully created,the Metrics stack will be created, which creates the following resources:

* A VCN that routes traffic to New Relic (alternatively, use an existing VCN)
* Application that contains a function
* Function Application that contains the `metrics-function` to forward metrics.
* A private Container Registry repository in your tenancy. The stack copies the function image (`function_image`, by default `docker.io/newrelic/beyond-oci-metric-function:latest`) into it, and the function runs from that copy.
* Service Connector that routes metrics to the Function Application

Apply the metrics stack once in each region that sends metrics. Each region gets its own repository, image copy, function and connector hubs, and each function pulls its image only from its own region's registry.

##### Function image and Container Registry access

The stack copies the image into the repository over the Container Registry API, logging in as `<tenancy_namespace>/<username>` with an auth token. The **Function image** section of the stack form controls this:

| Field | Default | Change it when |
|---|---|---|
| **Function image** | Uses `docker.io/newrelic/beyond-oci-metric-function:latest` | New Relic asks you to use a different image, or you want a version tag (for example `:1.5`) to choose when to upgrade |
| **Container Registry auth token** | The stack creates an auth token for the user who last created or edited the stack, keeps it for later upgrades, and deletes it when the stack is destroyed | See [When to enter your own auth token](#when-to-enter-your-own-auth-token) |
| **Container Registry username** | Uses the user who last created or edited the stack | You enter an auth token: enter the username of the token's owner |

###### When to enter your own auth token

Fill in both **Container Registry auth token** and **Container Registry username** when any of these apply:

* More than one person creates, edits, or applies the stack, or the person who created it might leave. A token the stack creates belongs to whoever last created or edited the stack, and later jobs need that user to still exist.
* The stack's user already has two auth tokens, the OCI maximum. Each regional stack creates its own token, so one user can set up at most two regions this way.
* Your organization doesn't allow creating auth tokens.

Use a dedicated user if you can. The same token and username work in every region, so enter them in each regional stack. The username must belong to the token's owner. If the token is later deleted or replaced, enter the new one before the next upgrade.

###### Finding the username and auth token

* **Username:** open the **Profile** menu (top right) and select **User settings** (or **My profile**). Copy the username shown at the top exactly as it appears, without the tenancy namespace; for example `jane@example.com`, also for users who sign in with single sign-on. For a user outside the **Default** identity domain, enter `<identity_domain_name>/<username>`. Tenancies that still federate through Oracle Identity Cloud Service show usernames that start with `oracleidentitycloudservice/`; copy them including that prefix.
* **Auth token:** on the same page, open **Tokens and keys**, go to **Auth tokens**, and select **Generate token**. Copy the token right away; the Console shows it only once. See [Getting an auth token](https://docs.oracle.com/en-us/iaas/Content/Registry/Tasks/registrygettingauthtoken.htm).

###### Permissions and timing

The user who applies the stack needs permission to manage repositories in the New Relic compartment. When the stack creates the token, the stack's user also needs the **Auth tokens** capability, which is enabled for users by default. A new auth token can take a few minutes to become active, and the stack retries during that time, so the copy step can show `Still creating...` for up to five minutes. The copy step's output is hidden because it uses the token; if the copy fails, the job log shows the full output in the error.

###### Troubleshooting

* **The copy fails with `rejected the username … and its auth token (401)`:** Container Registry doesn't accept that username and token. Check that the username belongs to the token's owner and is entered exactly as the Console shows it, without extra prefixes, and that the token still exists.
* **A job fails reading `data.oci_identity_user.registry_user`:** the user who last created or edited the stack no longer exists or can't be read by the user running the job. Edit the stack as your own user, or fill in both registry fields.

To upgrade the function, apply the stack again. If the tag in **Function image** points at a new image, the stack copies it and updates the function in place; otherwise nothing changes. Upgrades are per region, so apply the stack in every region.


Once the stack is created, metrics should be available in the New Relic portal. Open the query builder and run the following query to validate:
```
FROM Metric SELECT * where metricName like '%oci%'
```

### Metrics Function

The following table lists available environment variables that can be set for the function:

| Input | Type | Required | Description
| ----- | ---- |----------| -----------
| NR_METRIC_ENDPOINT | string | TRUE     | The metric api endpoint to forward metrics to (US, EU, or JP). Default: `US`
| FORWARD_TO_NR | string | TRUE     | Toggle forwarding to New Relic - Can be one of: `True,False`. Default: `True`
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
