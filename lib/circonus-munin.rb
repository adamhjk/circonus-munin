#!/usr/bin/env ruby
#
# munin-graphite.rb
# 
# A Munin-Node to Graphite bridge
#
# Author:: Adam Jacob (<adam@hjksolutions.com>)
# Copyright:: Copyright (c) 2008 HJK Solutions, LLC
# License:: GNU General Public License version 2 or later
# 
# This program and entire repository is free software; you can
# redistribute it and/or modify it under the terms of the GNU 
# General Public License as published by the Free Software 
# Foundation; either version 2 of the License, or any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# 

require 'socket'
require 'rack/request'
require 'rack/response'
require 'libxml'

class CirconusMunin 
  def initialize(host='localhost', port=4949)
    @munin = TCPSocket.new(host, port)
    @munin.gets
  end
  
  def get_response(cmd)
    @munin.puts(cmd)
    stop = false 
    response = Array.new
    while stop == false
      line = @munin.gets
      line.chomp!
      if line == '.'
        stop = true
      else
        response << line 
        stop = true if cmd == "list"
      end
    end
    response
  end
  
  def close
    @munin.close
  end
end

class CirconusMuninServer
  def initialize
    @munin = CirconusMunin.new
  end

  def call(env)
    req = Rack::Request.new(env)
    munin = CirconusMunin.new

    xml_document = LibXML::XML::Document.new
    resmon_results = LibXML::XML::Node.new("ResmonResults")

    munin.get_response("list")[0].split(" ").each do |metric|
      resmon_result = LibXML::XML::Node.new("ResmonResult")
      resmon_result["module"] = "MUNIN"
      resmon_result["metric"] = metric 

      begin_time = Time.now
      munin.get_response("fetch #{metric}").each do |line|
        line =~ /^(.+)\.value\s+(.+)$/
        field = $1
        value = $2
        metric = LibXML::XML::Node.new("metric")
        metric["name"] = field
        metric.content = value.to_s
        resmon_result << metric
      end
      end_time = Time.now
      runtime = end_time - begin_time

      last_runtime_seconds = LibXML::XML::Node.new("last_runtime_seconds")
      last_runtime_seconds.content = runtime.to_s
      resmon_result << last_runtime_seconds

      last_update = LibXML::XML::Node.new("last_update")
      last_update.content = Time.now.to_i.to_s
      resmon_result << last_update

      state = LibXML::XML::Node.new("state")
      state.content = "OK"
      resmon_result << state

      resmon_results << resmon_result
    end
  
    xml_document.root = resmon_results

    Rack::Response.new(xml_document.to_s, 200).finish
  end
end

