# frozen_string_literal: true

class PublishMatrixEventJob < ApplicationJob
  queue_as :matrix_events

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(event_data)
    MatrixEventService.send(:publish_event, event_data)
  end
end
