#!/usr/bin/env ruby

require_relative '01_readme_example'
require 'inquirex'
require 'stringio'

output = StringIO.new
exporter = Inquirex::Graph::MermaidExporter.new(DEFINITION)
output << exporter.export

source = <<~HTML
  <html>
    <head>
      <meta charset="utf-8">
    </head>
    <body>
    <meta charset="utf-8">
    <div class="mermaid">
      #{output.string}
    </div>
    <script type="module">
      import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
      mermaid.initialize({ startOnLoad: true });
    </script>
  </html>
HTML

if __FILE__ == $0
  File.write('mermaid.html', source)
  system("open mermaid.html")
  sleep 10

  at_exit do
    File.delete('mermaid.html')
  end
end
