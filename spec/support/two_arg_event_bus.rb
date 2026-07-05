# frozen_string_literal: true

# Adapter that bridges RuntimeEventRecorder's 2-arg publish(event_thread_id, event)
# to EventBus's 1-arg publish(event). Pre-existing source mismatch.
class TwoArgEventBus
  def initialize(inner)
    @inner = inner
  end

  def publish(_thread_id, event)
    @inner.publish(event)
  end

  def subscribe(thread_id, &)
    @inner.subscribe(thread_id, &)
  end

  def snapshot_since(thread_id, since_seq)
    @inner.snapshot_since(thread_id, since_seq)
  end

  def highest_seq(thread_id)
    @inner.highest_seq(thread_id)
  end

  def allocate_seq(thread_id)
    @inner.allocate_seq(thread_id)
  end
end
