require "sinatra/base"
require "json"
require_relative "lib/resizer"
require_relative "lib/storage"
require_relative "lib/queue"

module ImageProcessor
  class App < Sinatra::Base
    set :port, ENV.fetch("PORT", 3007)

    get "/health" do
      content_type :json
      { status: "ok" }.to_json
    end

    post "/api/resize" do
      content_type :json
      body = JSON.parse(request.body.read)
      job_id = Queue.enqueue("resize", {
        source_url: body["sourceUrl"],
        widths: body["widths"] || [200, 400, 800],
        format: body["format"] || "webp",
      })
      status 202
      { jobId: job_id, status: "queued" }.to_json
    end

    post "/api/optimize" do
      content_type :json
      body = JSON.parse(request.body.read)
      job_id = Queue.enqueue("optimize", {
        source_url: body["sourceUrl"],
        quality: body["quality"] || 80,
      })
      status 202
      { jobId: job_id, status: "queued" }.to_json
    end

    get "/api/jobs/:id" do
      content_type :json
      job = Queue.get_job(params[:id])
      halt 404, { error: "Job not found" }.to_json unless job
      job.to_json
    end
  end
end
