sequenceDiagram
    participant User
    participant SQSQueue
    participant CloudTrail
    participant Processor

    User->>SQSQueue: 1. Create Queue
    SQSQueue-->>CloudTrail: Log API Event (CreateQueue)
    User->>SQSQueue: 2. Send Message
    SQSQueue-->>CloudTrail: Log API Event (SendMessage)
    Processor->>SQSQueue: 3. Receive Message
    SQSQueue-->>CloudTrail: Log API Event (ReceiveMessage)
    Processor->>SQSQueue: 4. Delete Message
    SQSQueue-->>CloudTrail: Log API Event (DeleteMessage)
    Processor->>User: 5. Confirm Processing