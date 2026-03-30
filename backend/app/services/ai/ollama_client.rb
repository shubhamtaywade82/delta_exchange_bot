# frozen_string_literal: true

require "ollama-ai"

module Ai
  # OllamaClient provides cached access to local Ollama model responses for meta-configuration only.
  class OllamaClient
    def self.client
      @client ||= Ollama.new(credentials: { address: ENV.fetch("OLLAMA_URL", "http://localhost:11434") })
    end

    # @param prompt [String]
    # @return [String]
    def self.ask(prompt)
      response = client.generate(
        model: ENV.fetch("OLLAMA_MODEL", "llama3"),
        prompt: prompt,
        stream: false
      )
      response["response"].to_s
    end
  end
end
