require "net/http"
require "csv"
require "nokogiri"

Bankrupt = Struct.new(:id, :password) do
  TYPES = %w(Pesos lares)
  DATE_MAP = { ENE: 1, FEB: 2, MAR: 3, ABR: 4, MAY: 5, JUN: 6, JUL: 7, AGO: 8,
               SET: 9, OCT: 10, NOV: 11, DEC: 12 }

  Account = Struct.new(:currency, :number, :balance) do
    Balance = Struct.new(:date, :amount, :description)

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

    def fix_date(date)
      day = date[0..1]
      month = date[2..4].to_sym
      year = "20" + date[5..6]

      "#{DATE_MAP[month]}/#{day}/#{year}"
    end

    def balance
      balances = []

      CSV.parse(balance_as_csv, headers: true) do |row|
        date = fix_date(row["FECHA"])
        amount = row["HABER"].to_f - row["DEBE"].to_f
        description = row["CONCEPTO"]

        balances << Balance.new(date, amount, description)
      end

      balances[1...-1]
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
  puts account.number
  puts account.balance
end
