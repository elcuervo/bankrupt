#!/usr/bin/env ruby

require "net/http"
require "csv"
require "nokogiri"
require "json"
require "date"

Bankrupt = Struct.new(:id, :password, :company, :company_password) do
  Account = Struct.new(:type_name, :type, :hash, :currency, :number, :balance) do
    Balance = Struct.new(:date, :amount, :description)

    def filename
      "#{type_name}-#{number}-#{currency}"
    end

    def url
      "https://www.itaulink.com.uy/trx/cuentas/#{type}/#{hash}"
    end

    def file_url_for_last_days(format = "TXT")
      url + "/reporteEstadoCta/#{format}?diasAtras=5" # 5 is the only value that works :-/
    end

    def file_url_for_month(year = Time.now.year, month = Time.now.month, format = "TXT")
      url + "/reporteEstadoCta/#{format}?anio=#{year}&mes=#{month}"
    end

    def balance_from_itau(month)
      puts "Downloading from: " + file_url_for_last_days
      response = Bankrupt.get(file_url_for_last_days)
      response.body
    end

    def balance_as_csv(month = Time.now.month - 1)
      csv = %w(Date Amount Description).to_csv

      balance(month).each do |item|
        csv << [item.date, item.amount, item.description].to_csv
      end

      csv
    end

    def balance(month)
      balances = []

      balance_from_itau(month).each_line do |line|
        data = line.chomp.unpack("a7a4a7a2a15a15a*")
        date = Date.parse(data[2])
        amount = data[5].to_f - data[4].to_f
        description = data[6].gsub(/\s\s*/, " ")
        balances << Balance.new(date, amount, description) if transaction_data?(description)
      end

      balances
    end

    def transaction_data?(description)
      [/^CONCEPTO/, /^SALDO INICIAL/, /^SALDO FINAL/].
        none? { |e| description.to_s.strip.match?(e) }
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
      request["Cookie"] = Bankrupt.cookie if Bankrupt.cookie

      self.http.request(request)
    end
  end

  def login
    response = Bankrupt.post("https://www.itaulink.com.uy/trx/doLogin", {
      id: "login",
      tipo_usuario: "R",
      tipo_documento: "1",
      nro_documento: id,
      pass: password,
      password: password
    })

    cookie = response['Set-Cookie'].split('; ')[0]
    @accounts_url = response["Location"]
    puts "Account URL: #{@accounts_url}"

    Bankrupt.cookie = cookie
  end

  def company_login
    response = Bankrupt.post("https://www.itaulink.com.uy/appl/servlet/FeaServlet", {
      id: "login",
      tipo_usuario: "C",
      empresa: company.upcase,
      empresa_aux: company,
      pwd_empresa: company_password,
      usuario: id,
      usuario_aux: id,
      pwd_usuario: password
    })

    cookie = response['Set-Cookie'].split('; ')[0]
    @accounts_url = response["Location"]

    Bankrupt.cookie = cookie
  end

  def accounts
    @_accounts ||= begin
      response = Bankrupt.get(@accounts_url)
      json_string = response.body[/var mensajeUsuario = JSON.parse\('(.*)'\)\;/, 1]
      json = JSON.parse(json_string)
      accounts = []

      accounts_json = json["cuentas"]
      accounts_json.keys.each do |account_type|
        accounts_json[account_type].each do |account_data|
          accounts << Account.new(
            account_type,
            account_data["tipoCuenta"],
            account_data["hash"],
            account_data["moneda"],
            account_data["idCuenta"],
            account_data["saldo"]
          )
        end
      end

      puts "There are #{accounts.size} accounts. (#{accounts.map(&:number).join(",")})"

      accounts
    end
  end
end

if __FILE__ == $0
  account_id = ENV.fetch("CI", $1)
  password = ENV.fetch("PASSWORD", $2)

  bankrupt = Bankrupt.new(account_id, password)
  bankrupt.login
  puts "Fetching account information..."

  bankrupt.accounts.each do |account|
    filename = "#{account.filename}.csv"
    open(filename, "w") << account.balance_as_csv

    puts "#{filename} exported"
  end
end
