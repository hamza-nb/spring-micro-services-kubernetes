## 1. **Check if Kafka is running properly**

First, verify the pod is running:
```bash
kubectl get pods | grep kafka
```

Check the logs to ensure Kafka started successfully:
```bash
kubectl logs <kafka-pod-name>
```

## 2. **Access the Kafka pod**

Execute into the pod:
```bash
kubectl exec -it <kafka-pod-name> -- bash
```

## 3. **Create a test topic**

Inside the pod, use the kafka-topics script:
```bash
/opt/kafka/bin/kafka-topics.sh --create \
  --topic test-topic \
  --bootstrap-server localhost:9092 \
  --partitions 1 \
  --replication-factor 1
```

## 4. **List topics to verify**

```bash
/opt/kafka/bin/kafka-topics.sh --list \
  --bootstrap-server localhost:9092
```

## 5. **Test producing and consuming messages**

Produce a test message:
```bash
echo "test message" | /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic
```

Consume to verify:
```bash
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic test-topic \
  --from-beginning \
  --max-messages 1
```

## Common Issues to Check:

- **Port accessibility**: Ensure port 9092 (or your configured port) is accessible
- **Broker configuration**: Check that `KAFKA_CFG_ADVERTISED_LISTENERS` or equivalent is properly set
- **Storage**: Verify the pod has sufficient storage for topic data
- **Controller**: For kraft mode (apache/kafka:latest uses KRaft), ensure the controller is initialized