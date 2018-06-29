# Ruby interface for unoconv

# Prerequisites

* Install unoconv compatible version of Libre Office
* Install unoconv

## Usage:
```
Unoconv::Listener.open do |unoconv_listener|
  begin
    unoconv_listener.generate_pdf(doc_path) do |tmp_pdf_path|
      # Copy or move tmp_pdf_path to where you have to store it.
      # tmp_pdf_path is deleted after this block is executed.
    end
  rescue DocumentNotFound, FailedToCreatePDF => e
    # handle exception
  end
end
```
