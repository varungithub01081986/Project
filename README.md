### About repo

Проект помогает развернуть локальное окружение для деплоя Tiles API в On-Prem режиме.


### Requirements

Utilities docker, minikube and make should be installed

### Deployment steps

1. Optional parameters

| Parameter          | Comment                                       | Deafut                |
|--------------------|-----------------------------------------------|-----------------------|
| LIMIT_MEMORY       | Amount of RAM used for 1 node in cluster.     | 10240 (10Gb)          |
| LIMIT_CPUS         | Amount of CPU used for 1 node in cluster.     | 4                     |
| NODES_COUNT        | Amount of nodes in cluster.                   | 3                     |
| CLUSTER_NAME       | Cluster name.                                 | dgis-on-prem          |
| CLUSTER_DOMAIN     | Cluster domain (for ingresses).               | on-prem.loc           |
| ON_PREMISE_VERSION | 2gis-on-premise version.                      | 1.5.5                 |

To set optional parameters just run in terminal
``` sh
export $PARAMETER_NAME=$PARAMETER_VALUE
```

2. Run minikube cluster

``` sh
$ make create-cluster 
```

After this step k8s cluster will be created with ingress controller based on nginx and dns server for cluster domain.

3. Add DNS server for ingress domain (possible solution for Ubuntu)

   1. Switch `resolv.conf` to NetworkManager 
   ``` sh
   $ sudo mv /etc/resolv.conf /etc/resolv.conf.old
   $ sudo ln -s /var/run/NetworkManager/resolv.conf /etc/resolv.conf
   ```

   2. Enable and configure dnsmasq

      1. In main config file of NetworkManager add (or change) dns type
      ``` sh
      $ cd /etc/NetworkManager
      $ sudo vim NetworkManager.conf
      [main]
      dns=dnsmasq
      ...
      ```

      2. Add dnsmasq config for minikube
      ``` sh
      $ minikube ip -p $CLUSTER_NAME
      192.168.49.2
      $ sudo vim dnsmasq.d/minikube.conf
      server=/on-prem.loc/192.168.49.2
      ```

      3. Restart NetworkManager
      ``` sh
      $ sudo service NetworkManager restart
      ```

4. Deploy minio into the cluster

``` sh
$ make install-minio
```

5. Deploy docker registry

``` sh
$ make install-registry
```

**Important**: If docker registry have been already deployed with another `$CLUSTER_DOMAIN`, then directory `certs` should be deleted first before next deployment

``` sh
$ rm -rf certs
```

6. Add docker reistry self-signed certificate to trusted certificates

``` sh
$ make trust-registry-cert
```

7. Deploy cassandra

``` sh
$ make install-cassandra
```

wait for pod with cassandra will be started in cluster

8. Deploy kafka

``` sh
$ make install-kafka
```

9. Deploy postgresql

``` sh
$ make install-sandbox-postgres
```

10. Get key for API access from the form on [site](https://dev.urbi.ae/order/) or ask Denis Yakovlev

   Recieved key should be saved to dgctl.config.yaml file

11. Download images and data and save it to registry and minio

``` sh
$ make download-artifacts
```

#### [License service](license/)

#### [Keys service](keys/)

#### [Tiles](tiles/)

#### [Mapgl](mapgl/)

#### [Search service](search/)

#### [Traffic jams service](traffic/)

#### [Navigation service](navi/)

**Important** At the first launch .on-prem.loc could alert about wrong certificate. To fix it it is needed to mark certificate as trusted

### Cluster restart

If cluster was stopped via `minikube stop -p $CLUSTER_NAME` or your workstation was rebooted, then during new cluster creation, old one will be started.
May be in this case minikube will schedule all pods for one node, then persistence will be broken. To fix it one need to restart all pods

``` sh
$ kubectl delete pods --all
```

