class DocumentsController < ApplicationController

  before_action :set_document, only: [:download]

  def create
    @document = Document.create(document_params)
  end

  def download
    redirect_to @document.upload.expiring_url(30.seconds, :original)
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:direct_upload_url)
  end
end
