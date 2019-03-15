nodes:
  - address: ${master_public_ip}
    internal_address: 10.0.1.10
    user: centos
    role: [controlplane,etcd]
  - address: ${worker1_public_ip}
    internal_address: 10.0.1.11
    user: centos
    role: [worker]
  - address: ${worker2_public_ip}
    internal_address: 10.0.1.12
    user: centos
    role: [worker]
  - address: ${worker3_public_ip}
    internal_address: 10.0.1.13
    user: centos
    role: [worker]

services:
  etcd:
    snapshot: true
    creation: 6h
    retention: 24h