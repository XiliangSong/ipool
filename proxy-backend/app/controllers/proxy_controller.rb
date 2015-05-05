require 'excon'
require 'uri'
require 'monadic'

class ProxyController < ApplicationController
    def proxys
        @proxys = Proxy.all
        return render :json => {:data => @proxys}, :callback => params[:callback]
    end

    def add_proxy_api
        api_link = params[:proxyApi]
        begin
            #r = (HTTP).via(host, port).get(params[:url])
            r = Excon.get(api_link)
        rescue Exception => ex
            puts "An error of type #{ex.class} happened, message is #{ex.message}"
            return render :json => {"code" => -1, "msg" => "error", "body" => "add proxy api failed"}, :callback => params[:callback]
        end

        lines = r.body.split("\n")
        for line in lines
            host, port, user, passwd = line.gsub('\n', '').split(':')
            proxy = "http://%s:%s@%s:%s" % [user, passwd, host, port]
            add_proxy_url(proxy)
            #add proxy to redis & mysql
        end
        return render :json => {"code" => 0, "msg" => "error", "body" => "add proxy api Success"}, :callback => params[:callback]
    end

    def add_proxy_txt
        return render :json => {"code" => 0, "msg" => "error", "body" => "add proxy api Success"}, :callback => params[:callback]
    end

    def proxy_domains
        @proxys = ProxyDomain.all
        return render :json => {:data => @proxys}, :callback => params[:callback]
    end

    def allow_proxy
        ProxyDomain.where(:id => params[:ids]).update_all(:banned => 0, :banned_time => nil)
        return render :json => {"code" => 0, "msg" => "set all proxy available done"} 
    end

    def allow_all
        ProxyDomain.update_all(:banned => 0, :banned_time => nil)
        return render :json => {"code" => 0, "msg" => "set all proxy available done"}, :callback => params[:callback]
    end

    def ban_proxy
        ProxyDomain.where(:id => params[:ids]).update_all(:banned => 1, :banned_time => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
        return render :json => {"code" => 0, "msg" => "ban selected proxy available done"}, :callback => params[:callback]
    end

    def ban_all
        ProxyDomain.update_all(:banned => 1, :banned_time => Time.now.strftime("%Y-%m-%d %H:%M:%S"))
        return render :json => {"code" => 0, "msg" => "set all proxy available done"}, :callback => params[:callback]
    end


    def get_domain(url)
        #todo
        return "zillow.com"
    end

    def get_host_port(url)
        puts url
        uri = URI(url)
        puts uri
        return [uri.host, uri.port]

    end

    def fetch_data
        #params[:url] = "https://github.com/seaify"
        domain = get_domain(params[:url])
        proxys = $redis.zrevrange(domain, 0, 0)
        puts "hello"
        puts(proxys)
        puts "end"
        proxy = proxys[0]
        host, port = get_host_port(proxy)
        proxy_domain = proxy + '@' + domain
        puts proxy_domain
        $redis.hincrby(proxy_domain, 'total', 1)
        begin
            #r = (HTTP).via(host, port).get(params[:url])
            r = Excon.get(params[:url], :proxy => proxy)
        rescue Exception => ex
            puts "An error of type #{ex.class} happened, message is #{ex.message}"
            puts proxy_domain
            $redis.hmset(proxy_domain, 'banned', 1)
            $redis.hincrby(proxy_domain, 'total', 1)
            $redis.zadd(domain, -1.0, proxy)
            $redis.hmset(proxy_domain, 'banned_time', Time.now.to_i)
            return render :json => {"code" => -1, "msg" => "error", "body" => "proxy failed"} # don't do msg.to_json
        end


        if r.status== 200

            $redis.hincrby(proxy_domain, 'succ', 1)
            #$redis.zadd(host, proxy, $proxy_dict[proxy_domain]['succ'] / $proxy_dict[proxy_domain]['total'])

            return render :json => {"code" => 0, "msg" => "ok", "body" => r.body.to_s.encode('UTF-8', {:invalid => :replace, :undef => :replace, :replace => '?'})} # don't do msg.to_json
        else
            puts r.body
            return render :json => {"code" => -1, "msg" => "error", "body" => "proxy failed"} # don't do msg.to_json
        end

    end

    def add_proxy_url(proxy_url)
        method = proxy_url.split(':')[0]
        domains = (ProxyDomain.all.pluck(:domain) + ['zillow.com']).uniq

        p domains
        p domains.class

        #$redis.hmset(proxy_url, {'total' => 0, 'succ' => 0})
        for domain in domains
            proxy_domain_data = {"proxy" => proxy_url, "domain" => domain, "proxy_type" => method}
            proxy_domain = ProxyDomain.new(proxy_domain_data).save()
            p proxy_domain
            proxy_domain_url = proxy_url + '@' + domain
            $redis.hmset(proxy_domain_url, 'banned', 0)
            $redis.hmset(proxy_domain_url, 'total', 0)
            $redis.hmset(proxy_domain_url, 'succ', 0)
            #$redis.zadd(domain, {'total' => 0, 'succ' => 0})
            $redis.zadd(domain, 0, proxy_url)
        end
        proxy_data = {"proxy" => proxy_url, "proxy_type" => method}
        proxy = Proxy.new(proxy_data).save()
        p proxy

    end

    def add_proxy(proxy_url)
        add_proxy_url(proxy_url)
        render :json => {"msg" => "ok"} # don't do msg.to_json
    end

    def testme
        respond_to do |format|
            msg = {:status => "ok", :message => "Success!", :html => "<b>...</b>"}
            format.json { render :json => msg } # don't do msg.to_json
        end
    end
end
