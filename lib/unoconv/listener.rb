require 'securerandom'
require 'shellwords'
require 'timeout'

# Usage:
# Unoconv::Listener.open do |unoconv_listener|
#   begin
#     unoconv_listener.generate_pdf(doc_path) do |tmp_pdf_path|
#       # Copy or move tmp_pdf_path to where you have to store it.
#       # tmp_pdf_path is deleted after this block is executed.
#     end
#   rescue DocumentNotFound, FailedToCreatePDF => e
#     # handle exception
#   end
# end

class Unoconv::Listener
  # errors during generated_pdf
  class DocumentNotFound < StandardError; end
  class FailedToCreatePDF < StandardError; end
  class NotStarted < StandardError; end
  # errors during open / start
  class LibreOfficeAlreadyOpen < StandardError; end
  class UnoconvAlreadyOpen < StandardError; end

  STARTUP_SLEEP = 20.0
  OUTDIR = 'tmp'

  def self.open(&block)
    instance = new
    instance.start
    block.call(instance)
  ensure
    instance&.stop
  end

  def generate_pdf(doc_path, output_format, &block)
    tmp_pdf_path = nil

    unless started?
      raise NotStarted, "Call #{self.class}#start before calling #{__method__}"
    end

    unless File.exists?(doc_path)
      raise DocumentNotFound, "File does not exist: #{doc_path}"
    end

    # Libre Office and unoconv can both crash,
    # so we need to wrap it in a timeout and restart the services if they time out
    Timeout::timeout(30) do
      begin
        tmp_pdf_path = unoconv_generate_pdf(doc_path, output_format)
        block.call(tmp_pdf_path)
      rescue Timeout::Error
        restart
        convert_to_pdf(doc_path, &block)
      end
    end

  ensure
    File.delete(tmp_pdf_path) if tmp_pdf_path && File.exists?(tmp_pdf_path)
  end

  def start
    # If the unoconv process is already running, starting a new process will
    # make it freeze. The output is not returned when the process is frozen
    # but the output is shown in the terminal as:
    #   LibreOffice crashed - exit code: 0
    #
    # To avoid this I try to raise an error if unoconv is already open.
    raise_if_already_open

    puts "Starting: unoconv --listener"
    @unoconv_pid = Process.spawn("#{unoconv_cmd} --listener")

    puts "Waiting #{STARTUP_SLEEP} sec for Libre Office and unoconv to start..."
    sleep(STARTUP_SLEEP)
    puts "Expecting Libre Office and unoconv to be open and ready now!"
  end

  def stop
    puts "Stopping: unoconv --listener"
    kill_soffice
    kill_unoconv
  end

  private

  def started?
    @unoconv_pid.present?
  end

  def unoconv_generate_pdf(doc_path, output_format)
    out_path = File.join(OUTDIR, "#{SecureRandom.uuid}.pdf")
    options = [
      '--no-launch',
      "-f #{output_format}",
      '-P PaperFormat=A4',
      "-o #{Shellwords.escape(out_path)}",
      Shellwords.escape(doc_path)
    ]
    unless system("#{unoconv_cmd} #{options.join(' ')}")
      raise FailedToCreatePDF, "might be unable to convert: #{doc_path}"
    end

    out_path
  end

  def restart
    puts "Restarting #{self.class}"
    stop
    start
  end

  def kill_unoconv
    puts "Stopping: #{unoconv_pname} (unoconv)"
    kill_pid(@unoconv_pid)
    kill_pid(find_unoconv_pid)
    @unoconv_pid = nil
  end

  # Kill Libre Office
  def kill_soffice
    puts "Stopping: #{soffice_pname} (Libre Office)"
    kill_pid(find_soffice_pid)
  end

  def kill_pid(pid)
    return unless pid.present?
    Process.kill("TERM", pid)
    Process.wait
  rescue Errno::ESRCH
    # No such process
    # In this case simply return without re-raising.
  rescue Errno::ECHILD
    # No child processes
    # Nothing to wait for. In this case simply return without re-raising.
  end

  # PID for Libre Office
  def find_soffice_pid
    %x(pgrep #{soffice_pname}).presence&.to_i
  end

  # PID for unoconv
  def find_unoconv_pid
    %x(pgrep #{unoconv_pname}).presence&.to_i
  end

  # Process name for Libre Office
  def soffice_pname
    'soffice'
  end

  # Process name for unoconv
  def unoconv_pname
    'LibreOffi'
  end

  def raise_if_already_open
    raise UnoconvAlreadyOpen,     unoconv_error if find_unoconv_pid.present?
    raise LibreOfficeAlreadyOpen, soffice_error if find_soffice_pid.present?
  end

  def unoconv_error
    "unoconv is already running. #{error_advice}"
  end

  def soffice_error
    "Libre Office is already open. #{error_advice}"
  end

  def error_advice
    "Make sure it's only spawned once. To reset manually run: #{killall_cmd}"
  end

  # Depends on unoconv (and Libre Office) being installed
  def unoconv_cmd
    # Workaround for Mac users with newer versions of Libre Office
    @unoconv_cmd ||=
      if use_mac_workaround?
        "#{mac_python_path} $(which unoconv)"
      else
        "unoconv"
      end
  end

  def mac_python_path
    @mac_python_path ||=
      Dir["/Applications/LibreOffice.app/Contents/*/python"].first
  end

  def use_mac_workaround?
    return @use_mac_workaround unless @use_mac_workaround.nil?
    @use_mac_workaround = RUBY_PLATFORM.include?("darwin")
  end

  # Command to kill both Libre Office and unoconv
  def killall_cmd
    "kill -9 `pgrep #{soffice_pname} #{unoconv_pname}`"
  end
end
