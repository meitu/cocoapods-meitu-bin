require 'digest'
module Pod
  class Command
    class Bin < Command
      class GetChecksum < Bin
        self.summary = '根据输入的podfile路径返回该podfile对应checksum(类似文件MD5值)'
        self.description = <<-DESC
          #{summary}
        DESC

        def self.options
          [
            %w[--path=podfile路径]
          ].concat(super).uniq
        end

        def initialize(argv)
          @path = argv.option('path', "")
          super
        end

        def run
          puts calculate_checksum(@path)
        end
        # 计算checksum值
        def calculate_checksum(file_path)
          return "" unless File.exist?(file_path)
          content = File.read(file_path)
          checksum = Digest::SHA1.hexdigest(content)
          checksum = checksum.encode('UTF-8') if checksum.respond_to?(:encode)
          return checksum
        end

      end
    end
  end
end