class EmailsController < ApplicationController
  def index
    render plain: "Email System - Ready for Testing"
  end

  def create
    render plain: "Email created"
  end

  def destroy
    render plain: "Email deleted"
  end

  def bulk_send
    render plain: "Bulk send initiated"
  end

  def import_csv
    render plain: "CSV import initiated"
  end
end