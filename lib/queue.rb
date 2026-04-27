require "redis"
require "json"
require "securerandom"

module ImageProcessor
  class Queue
    REDIS = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

    def self.enqueue(type, payload)
      id = SecureRandom.uuid
      job = { id: id, type: type, payload: payload, status: "queued", created_at: Time.now.iso8601 }
      REDIS.set("job:#{id}", job.to_json)
      REDIS.lpush("jobs:pending", id)
      id
    end

    def self.get_job(id)
      raw = REDIS.get("job:#{id}")
      return nil unless raw
      JSON.parse(raw)
    end
  end
end
