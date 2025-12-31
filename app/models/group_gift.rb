class GroupGift < ApplicationRecord
  self.table_name = :group_gifts
  self.primary_key = :gift_id

  before_validation :generate_gift_id, on: :create

  validates :gift_id, presence: true, uniqueness: true
  validates :total_amount, numericality: { greater_than: 0, less_than_or_equal_to: 50000 }
  validates :currency, presence: true, inclusion: { in: %w[USD EUR GBP] }
  validates :count, numericality: { greater_than_or_equal_to: 2, less_than_or_equal_to: 100 }
  validates :distribution, inclusion: { in: %w[random equal] }
  validates :remaining, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[active fully_opened expired] }
  validates :room_id, presence: true
  validates :expires_at, presence: true

  belongs_to :creator, class_name: "User", foreign_key: :creator_id

  has_many :openings, class_name: "GiftOpening", foreign_key: :group_gift_id, dependent: :destroy

  scope :active, -> { where(status: "active") }
  scope :not_expired, -> { where("expires_at > ?", Time.current) }
  scope :by_room, ->(room_id) { where(room_id: room_id) }

  def self.distribution_algorithms
    {
      random: :calculate_random_distribution,
      equal: :calculate_equal_distribution
    }
  end

  def self.lock_gift_for_opening(gift_id)
    GroupGift.where(gift_id: gift_id).lock.first
  end

  def can_open?(user_id)
    return false if status != "active"
    return false if Time.current > expires_at
    return false if remaining <= 0
    return false if already_opened?(user_id)

    true
  end

  def already_opened?(user_id)
    openings.exists?(user_id: user_id)
  end

  def open_gift!(user_id, user_context = {})
    transaction do
      gift = self.class.lock_gift_for_opening(gift_id)

      raise GiftError.new("GIFT_EMPTY", "Gift has already been fully opened") if gift.remaining <= 0

      raise GiftError.new("ALREADY_OPENED", "You have already opened this gift") if gift.openings.exists?(user_id: user_id)

      if Time.current > gift.expires_at
        gift.update!(status: "expired")
        raise GiftError.new("GIFT_EXPIRED", "Gift has expired")
      end

      amount = calculate_amount_for_opening

      opening = gift.openings.create!(
        user_id: user_id,
        amount: amount,
        user_context: user_context
      )

      gift.decrement!(:remaining)

      if gift.remaining <= 0
        gift.update!(status: "fully_opened")
      end

      opening
    end
  end

  def calculate_amount_for_opening
    if distribution == "equal"
      calculate_equal_distribution.first
    else
      calculate_random_distribution.first
    end
  end

  def generate_distribution!
    amounts = case distribution
    when "equal"
      self.class.calculate_equal_distribution(total_amount, count)
    when "random"
      self.class.calculate_random_distribution(total_amount, count)
    else
      []
    end

    update!(distribution_amounts: amounts.shuffle)
  end

  def leaderboard
    openings.order(amount: :desc).limit(10).map do |opening|
      {
        user_id: opening.user_id,
        amount: opening.amount,
        opened_at: opening.created_at
      }
    end
  end

  def self.calculate_equal_distribution(total_amount, count)
    base_amount = (total_amount / count).round(2)
    remainder = (total_amount - base_amount * count).round(2)

    amounts = Array.new(count, base_amount)
    amounts[0] += remainder if remainder > 0

    amounts
  end

  def self.calculate_random_distribution(total_amount, count)
    amounts = []
    remaining = total_amount

    (count - 1).times do
      min_amount = (total_amount * 0.1 / count).round(2)
      max_amount = (remaining * 0.7).round(2)
      amount = rand(min_amount..max_amount).round(2)

      amounts << amount
      remaining -= amount
    end

    amounts << remaining.round(2)
    amounts.shuffle
  end

  private

  def generate_gift_id
    self.gift_id ||= "gift_#{SecureRandom.alphanumeric(12)}"
  end

  def calculate_amount_for_opening
    return 0.0 unless distribution_amounts.present? && distribution_amounts.any?

    idx = openings.count
    return distribution_amounts[idx] if idx < distribution_amounts.length

    0.0
  end

  class GiftError < StandardError
    attr_reader :code

    def initialize(code, message)
      super(message)
      @code = code
    end
  end
end

class GiftOpening < ApplicationRecord
  self.table_name = :gift_openings
  self.primary_key = :id

  belongs_to :group_gift, class_name: "GroupGift", foreign_key: :group_gift_id

  validates :group_gift_id, presence: true
  validates :user_id, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :recent, -> { order(created_at: :desc) }
end
