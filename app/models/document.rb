# == Schema Information
#
# Table name: documents
#
#  id                  :integer          not null, primary key
#  direct_upload_url   :string(255)      not null
#  upload_file_name    :string(255)
#  upload_content_type :string(255)
#  upload_file_size    :integer
#  upload_updated_at   :datetime
#  processed           :boolean          default(FALSE), not null
#  created_at          :datetime
#  updated_at          :datetime
#

class Document < ActiveRecord::Base

  BUCKET_NAME = Rails.application.secrets.aws['s3_bucket_name']

  # Environment-specific direct upload url verifier screens for malicious posted upload locations.
  #
  # @note CORS required on s3 buckets to facilitate direct upload.
  #
  # @note Format matches that specified in s3-uploader_form:
  #   "uploads/{timestamp}-{unique_id}-#{SecureRandom.hex}/${filename}"
  #
  # @example Valid URL
  #   "https://s3.amazonaws.com/myapp-development/uploads/92a7d2c5-83de-47ad-981c-c6e391531a0e/foo.jpg"
  #
  # @example Invalid URL
  #   "http://haxor.com/virus.exe"
  #
  # @example CORS config
  #   <?xml version="1.0" encoding="UTF-8"?>
  #   <CORSConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  #       <CORSRule>
  #           <AllowedOrigin>*</AllowedOrigin>
  #           <AllowedMethod>POST</AllowedMethod>
  #           <MaxAgeSeconds>3000</MaxAgeSeconds>
  #           <AllowedHeader>*</AllowedHeader>
  #       </CORSRule>
  #   </CORSConfiguration>
  #
  DIRECT_UPLOAD_URL_FORMAT = %r{\Ahttps:\/\/s3\.amazonaws\.com\/#{BUCKET_NAME}\/(?<path>uploads\/.+\/(?<filename>.+))\z}.freeze
  
  has_attached_file :upload

  validates :direct_upload_url, presence: true, format: { with: DIRECT_UPLOAD_URL_FORMAT }
    
  before_create :set_upload_attributes
  after_create :queue_finalize_and_cleanup

  # Store an unescaped version of the escaped URL that Amazon returns from direct upload.
  def direct_upload_url=(escaped_url)
    write_attribute(:direct_upload_url, (CGI.unescape(escaped_url) rescue nil))
  end
    
  # Update the document upload and manually re-process
  def update_file(params)
    self.processed = false
    self.attributes = params
    set_upload_attributes
    save!
    Document.delay.finalize_and_cleanup(id)
  end
  
  # Determines if file requires post-processing (image resizing, etc)
  def post_process_required?
    %r{^(image|(x-)?application)/(bmp|gif|jpeg|jpg|pjpeg|png|x-png)$}.match(upload_content_type).present?
  end
  
  # Final upload processing step:
  #
  # 1) If the file does not require processing, manually copy direct uplaod to
  #   the location that Paperclip expects, saving transfer time/cost.
  #   If the file requires post-processing, set the direct_upload_url as the document's remote source,
  #   which instantiates download, process, and re-upload of the file via Paperclip callbacks.
  # 2) Flag document as processed
  # 3) Delete the temp upload from s3.
  #
  # @see http://docs.aws.amazon.com/AmazonS3/latest/dev/CopyingObjectUsingRuby.html
  def self.finalize_and_cleanup(id)
    document = Document.find(id)
    direct_upload_url_data = DIRECT_UPLOAD_URL_FORMAT.match(document.direct_upload_url)
    s3 = AWS::S3.new
    
    if document.post_process_required?
      document.upload = URI.parse(URI.escape(document.direct_upload_url))
    else
      paperclip_file_path = "documents/uploads/#{id}/original/#{direct_upload_url_data[:filename]}"
      s3.buckets[BUCKET_NAME].objects[paperclip_file_path].copy_from(direct_upload_url_data[:path])
    end

    document.processed = true
    document.save
    
    s3.buckets[BUCKET_NAME].objects[direct_upload_url_data[:path]].delete
  end
  
  protected
  
  # Optional: Set attachment attributes from the direct upload instead of original upload callback params
  # @note Retry logic handles occasional S3 "eventual consistency" lag.
  def set_upload_attributes
    tries ||= 5
    direct_upload_url_data = DIRECT_UPLOAD_URL_FORMAT.match(direct_upload_url)
    s3 = AWS::S3.new
    direct_upload_head = s3.buckets[BUCKET_NAME].objects[direct_upload_url_data[:path]].head

    self.upload_file_name     = direct_upload_url_data[:filename]
    self.upload_file_size     = direct_upload_head.content_length
    self.upload_content_type  = direct_upload_head.content_type
    self.upload_updated_at    = direct_upload_head.last_modified
  rescue AWS::S3::Errors::NoSuchKey => e
    tries -= 1
    if tries > 0
      sleep(3)
      retry
    else
      raise e
    end
  end
  
  # Queue final file processing
  def queue_finalize_and_cleanup
    Document.delay.finalize_and_cleanup(id)
  end

end
