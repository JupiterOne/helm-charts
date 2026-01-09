CRD Mapping Configuration to customize how CRDs are ingested
Can be set via --set-file crdMappingConfig=path/to/file.yaml
The following is an example configuration.

crdMappingConfig: |
 resources:
   - name: integrationrunners.integrations.jupiterone.io
     version: v1
     _type: kube_cr_integration_runner
     _class: Process
     propertyToFieldMap:
       _key: metadata.uid
       name: metadata.name
       namespace: metadata.namespace
       createdOn: metadata.creationTimestamp
       accountId: spec.accountId
       collectorId: spec.collectorId
       collectorPoolId: spec.collectorPoolId
       jupiterOneEnvironment: spec.jupiterOneEnvironment
       secretAPITokenName: spec.secretAPITokenName
       secretName: spec.secretName
       syncIntervalSeconds: spec.syncIntervalSeconds
   - name: integrationinstancejobs.integrations.jupiterone.io
     _type: kube_cr_integration_instance_job
     _class: Task
     propertyToFieldMap:
       _key: metadata.uid
       name: metadata.name
       namespace: metadata.namespace
       createdOn: metadata.creationTimestamp
       accountId: spec.accountId
       certificateIdentity: spec.certificateIdentity
       image: spec.image
       integrationDefinitionName: spec.integrationDefinitionName
       integrationInstanceId: spec.integrationInstanceId
       integrationInstanceJobId: spec.integrationInstanceJobId
       integrationRunnerName: spec.integrationRunnerName
       secretName: spec.secretName
 relationships:
   - _class: HAS
     sourceType: kube_cr_integration_runner
     targetType: kube_secret
     matchBy:
       secretName: name
       namespace: namespace
   - _class: HAS
     sourceType: kube_cr_integration_instance_job
     targetType: kube_secret
     matchBy:
       secretName: name
       namespace: namespace
   - _class: HAS
     sourceType: kube_cr_integration_instance_job
     targetType: kube_cr_integration_runner
     matchBy:
       integrationRunnerName: name
       namespace: namespace