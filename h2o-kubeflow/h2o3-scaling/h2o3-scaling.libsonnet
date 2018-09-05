local k = import 'k.libsonnet';
local deployment = k.extensions.v1beta1.deployment;
local container = deployment.mixin.spec.template.spec.containersType;
local storageClass = k.storage.v1beta1.storageClass;
local service = k.core.v1.service;
local networkPolicy = k.extensions.v1beta1.networkPolicy;
local networkSpec = networkPolicy.mixin.spec;

{
  parts:: {
    deployment:: {
      local defaults = {
        imagePullPolicy:: "IfNotPresent",
      },

      modelHPA(name, namespace, replicas, labels={ app: name }): {
        local userObj = std.split(namespace, "@"),
        apiVersion: "autoscaling/v2beta1",
        kind: "HorizontalPodAutoscaler",
        metadata: {
          labels: labels,
          name: name,
          namespace: userObj[0],
        },
        spec: {
          scaleTargetRef: {
            apiVersion: "extensions/v1beta1",
            kind: "Deployment",
            name: name,
          },
          minReplicas: replicas,
          maxReplicas: 10,
          metrics: [
            {
              type: "Resource",
              resource: {
                name: "memory",
                targetAverageUtilization: 30
              },
            },
          ],
        },
      },

      modelService(name, namespace, labels={ app: name }): {
        local userObj = std.split(namespace, "@"),
        apiVersion: "v1",
        kind: "Service",
        metadata: {
          labels: labels,
          name: name,
          namespace: userObj[0],
        },
        spec: {
          ports: [
            {
              port: 54321,
              protocol: "TCP",
              targetPort: 54321,
            },
          ],
          selector: labels,
          type: "LoadBalancer",
        },
      },

      modelServer(name, namespace, memory, cpu, replicas, modelServerImage, labels={ app: name },):
        local userObj = std.split(namespace, "@");
        local volume = {
          name: "local-data",
          namespace: userObj[0],
          emptyDir: {},
        };
        base(name, namespace, memory, cpu, replicas, modelServerImage, labels),

      local base(name, namespace, memory, cpu, replicas, modelServerImage, labels) =
        {
          local userObj = std.split(namespace, "@"),
          apiVersion: "extensions/v1beta1",
          kind: "Deployment",
          metadata: {
            name: name,
            namespace: userObj[0],
            labels: labels,
          },
          spec: {
            strategy: {
                rollingUpdate: {
                    maxSurge: 1,
                    maxUnavailable: 1
                },
                type: "RollingUpdate"
            },
            replicas: replicas,
            template: {
              metadata: {
                labels: labels,
              },
              spec: {
                containers: [
                  {
                    name: name,
                    image: modelServerImage,
                    imagePullPolicy: defaults.imagePullPolicy,
                    env: [
                      {
                        name: "MEMORY",
                        value: memory,
                      }
                    ],
                    ports: [
                      {
                        containerPort: 54321,
                        protocol: "TCP"
                      },
                    ],
                    workingDir: "/opt",
                    command: [
                      "java",
                      "-Xmx$(MEMORY)g",
                      "-jar",
                      "h2o.jar",
                      "-name",
                      name,
                      "-flow_dir",
                      "/home/" + userObj[0]
                    ],
                    resources: {
                      requests: {
                        memory: memory + "Gi",
                        cpu: cpu,
                      },
                      limits: {
                        memory: memory + "Gi",
                        cpu: cpu,
                      },
                    },
                    volumeMounts: [                      
                      {
                        mountPath: "/home/" + userObj[0],
                        name: userObj[0] + "-pvc"
                      }
                    ],
                    stdin: true,
                    tty: true,
                  },
                ],
                volumes: [
                  {
                    name: userObj[0] + "-pvc",
                    persistentVolumeClaim: {
                      claimName: userObj[1]
                    }
                  }
                ],
                dnsPolicy: "ClusterFirst",
                restartPolicy: "Always",
                schedulerName: "default-scheduler",
                securityContext: {},
              },
            },
          },
        },
    },
  },
}
