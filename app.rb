require "./bankrupt"
require "tmpdir"
require "cuba"
require "cuba/render"
require 'zip/zip'
require "date"

Cuba.plugin Cuba::Render
Cuba.define do
  on(root) { res.write view("home") }

  on post, "accounts" do
    account, password = req.params["username"], req.params["password"]
    company, company_password = req.params["company"], req.params["company_password"]

    bankrupt = Bankrupt.new(account, password, company, company_password)

    if !company.nil?
      bankrupt.company_login
    else
      bankrupt.login
    end

    puts "Fetching account information..."

    zip_name = "accounts-#{account}-#{Time.now.strftime("%Y%m%dT%H%M%S")}.zip"
    compressed = Tempfile.new(zip_name)

    Zip::ZipOutputStream.open(compressed.path) do |zip|
      bankrupt.accounts.each do |account|
        file_name = "#{account.filename}.csv"
        zip.put_next_entry(file_name)
        zip.print account.balance_as_csv(req.params["year"], req.params["month"])
      end
    end

    res["Content-Type"] = "application/zip"
    res["Content-Disposition"] = "attachment; filename=#{zip_name}"

    res.write compressed.read

    compressed.close

  end
end
