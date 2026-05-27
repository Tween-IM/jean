class Api::V1::Social::ReportsController < Api::V1::Social::BaseController
  def create
    require_scope("social:engage")

    video = find_video
    report = video.social_reports.new(report_params)
    report.reporter_user_id = @current_user.matrix_user_id

    if report.save
      render json: { report: report_json(report) }, status: :created
    else
      render_errors(report)
    end
  end

  private

  def report_params
    params.require(:report).permit(:reason, :details, metadata: {})
  end
end
