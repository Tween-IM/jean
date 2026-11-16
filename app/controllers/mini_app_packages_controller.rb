# Published mini-app code is distributable. Pending packages remain behind staff authentication.
class MiniAppPackagesController < ActionController::Base
  def show
    app = MiniApp.active.find_by!(app_id: params[:app_id], version: params[:version])
    raise ActiveRecord::RecordNotFound unless app.bundle.attached? && app.manifest.dig('bundle', 'version') == app.version
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Content-Security-Policy'] = "sandbox; default-src 'none'"
    redirect_to rails_blob_path(app.bundle, disposition: 'attachment')
  end
end
