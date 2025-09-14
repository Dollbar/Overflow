# Inference Runtime

The runtime manages model loading, paged KV/state, continuous batching, prefill/decode scheduling,
multi-NPU resources, recovery, and service metrics. It consumes compiler artifacts and uses a stable ABI
to communicate with the driver.

The model-serving protocol and device runtime remain separate so network API changes do not alter hardware ABI.
