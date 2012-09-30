module Nordea
  module FileTransfer
    class Client
      include Config

      def initialize(options = {})
        Nordea::FileTransfer.config.keys.each do |key|
          send("#{key}=", options[key] || Nordea::FileTransfer.config.send(key))
        end

        @savon_client = Savon::Client.new do |wsdl, http, wsse|
          # Do not fetch wsdl document, use namespace and endpoint instead.
          wsdl.document = "https://filetransfer.nordea.com/services/CorporateFileService?wsdl"
          wsdl.endpoint = "https://filetransfer.nordea.com/services/CorporateFileService"
          certs = Akami::WSSE::Certs.new(:cert_file => @cert_file, :private_key_file => @private_key_file)
          wsse.signature = Akami::WSSE::Signature.new(certs)
          wsse.verify_response = false
        end
      end

      def get_user_info(&block)
        request :get_user_info, &block
      end

      def download_file_list(&block)
        request :download_file_list, &block
      end

      def download_file(&block)
        request :download_file, &block
      end

      def upload_file(&block)
        request :upload_file, &block
      end

      private

      def cert
        OpenSSL::X509::Certificate.new(File.read(cert_file))
      end

      def private_key
        OpenSSL::PKey::RSA.new(File.read(private_key_file), private_key_password)
      end

      # Actions:
      # * :delete_file,
      # * :download_file,
      # * :download_file_list,
      # * :get_user_info,
      # * :upload_file
      def request(action)
        response = @savon_client.request action do
          soap.namespaces["xmlns"]      = "http://model.bxd.fi"
          soap.namespaces["xmlns:xsns"] = "http://bxd.fi/CorporateFileService"

          timestamp = Time.now

          req = Request.new
          req.cert = cert
          req.private_key = private_key

          req.request_header = RequestHeader.new
          req.request_header.sender_id   = sender_id
          req.request_header.request_id  = timestamp.to_i
          req.request_header.timestamp   = timestamp
          req.request_header.language    = language
          req.request_header.user_agent  = user_agent
          req.request_header.receiver_id = receiver_id

          req.application_request = ApplicationRequest.new
          req.application_request.customer_id = customer_id
          req.application_request.command     = action.to_s.camelcase
          req.application_request.timestamp   = timestamp
          req.application_request.environment = environment
          req.application_request.software_id = software_id

          if block_given?
            yield req.request_header, req.application_request
          end

          soap.body = req.to_hash
        end
        response_params = response.to_hash[:"#{action}out"]
        if response_params[:response_header][:response_code] == "00"
          Response.new(response_params)
        else
          raise Error.new(
            response_params[:response_header][:response_code],
            response_params[:response_header][:response_text]
          )
        end
      end
    end
  end
end
