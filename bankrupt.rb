require "net/http"
require "nokogiri"

Bankrupt = Struct.new(:id, :password) do
  TYPES = %w(Pesos lares)

  Account = Struct.new(:currency, :number, :balance) do
    def balance_as_csv
      url = "https://www.itaulink.com.uy/appl/servlet/FeaServletDownload"

      response = Bankrupt.post(url, {
        nro_cuenta: number,
        id: "bajar_archivo",
        mes_anio: "null",
        fecha: "",
        tipo_archivo: "E"
      })

      response.body
    end
  end

  class << self
    attr_accessor :cookie

    def http
      @_http ||= begin
        uri = URI.parse("https://www.itaulink.com.uy/")
        http = Net::HTTP.new(uri.host, uri.port)
        http.set_debug_output $stdout if ENV["DEBUG"]
        http.use_ssl = true
        http
      end
    end

    def get(url)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Cookie"] = Bankrupt.cookie if Bankrupt.cookie

      self.http.request(request)
    end

    def post(url, data)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data(data)
      request["Cookie"] = Bankrupt.cookie if Bankrupt.respond_to?(:cookie)

      self.http.request(request)
    end
  end

  def login
    response = Bankrupt.post("https://www.itaulink.com.uy/appl/servlet/FeaServlet", {
      id: "login",
      tipo_usuario: "R",
      tipo_documento: "1",
      nro_documento: id,
      password: password
    })

    cookie = response['Set-Cookie'].split('; ')[0]
    @accounts_url = response["Location"]

    Bankrupt.cookie = cookie
  end

  def accounts
    @_accounts ||= begin
      response = Bankrupt.get(@accounts_url)
      parser = Nokogiri::HTML(response.body)
      accounts = []

      TYPES.each do |type|
        location = ".//td[./font[contains(.,'#{type}')]]/"
        number = parser.search("#{location}preceding-sibling::*").text
        balance = parser.search("#{location}following-sibling::*").text.split[0]

        accounts << Account.new(type, number, balance)
      end

      accounts
   end
  end
end

bankrupt = Bankrupt.new(ENV["CI"], ENV["PASSWORD"])
bankrupt.login
bankrupt.accounts.each do |account|
  puts account.balance_as_csv
end
