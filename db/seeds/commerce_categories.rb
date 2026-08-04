# frozen_string_literal: true

# Commerce category taxonomy — 106 top-level categories with subcategories.
# Run: rails runner "load(Rails.root.join('db/seeds/commerce_categories.rb'))"

puts "Seeding commerce categories..."

cats = {
  # ════════════════════════════════════════════════════════════════════════
  # VEHICLES (101-113)
  # ════════════════════════════════════════════════════════════════════════
  101 => { name: "Passenger Cars", icon: "car", subs: %w[
    SUV Sedan Hatchback Coupe Convertible Wagon Pickup Van Electric Luxury
  ]},
  102 => { name: "SUVs & Crossovers", icon: "car", subs: %w[
    Compact-SUV Mid-Size-SUV Full-Size-SUV Luxury-SUV 7-Seater
  ]},
  103 => { name: "Commercial Trucks", icon: "truck", subs: %w[
    Light-Truck Medium-Truck Heavy-Truck Flatbed Tipper Tanker Refrigerated-Truck
  ]},
  104 => { name: "Buses & Minibuses", icon: "bus", subs: %w[
    Minibus Coaster School-Bus City-Bus Luxury-Bus Shuttle
  ]},
  105 => { name: "Motorcycles & Scooters", icon: "motorcycle", subs: %w[
    Standard Sport Cruiser Scooter Tricycle-Electric-Bike Dirt-Bike
  ]},
  106 => { name: "Electric & Hybrid Vehicles", icon: "zap", subs: %w[
    Battery-EV Plug-In-Hybrid Hybrid FCEV Electric-Motorcycle
  ]},
  107 => { name: "Watercraft & Marine", icon: "boat", subs: %w[
    Speedboat Fishing-Boat Kayak Jet-Ski Yacht Canoe Pontoon
  ]},
  108 => { name: "Auto Parts & Accessories", icon: "wrench", subs: %w[
    Engine-Parts Brake-Parts Electrical-Parts Body-Parts Interior-Accessories Exterior-Accessories Filters Batteries
  ]},
  109 => { name: "Car Electronics & Audio", icon: "speaker-simple", subs: %w[
    Head-Unit Amplifier Speaker Subwoofer Dash-Cam GPS-Navigation Reverse-Camera
  ]},
  110 => { name: "Tires & Wheels", icon: "circle", subs: %w[
    Car-Tires Truck-Tires Alloy-Rims Steel-Rims Tire-Accessories Run-Flat
  ]},
  111 => { name: "Automotive Services & Maintenance", icon: "wrench", subs: %w[
    Oil-Change Brake-Service Engine-Repair Car-Wash Diagnostic AC-Service Suspension Towing
  ]},
  112 => { name: "Heavy Construction Machinery", icon: "hard-hat", subs: %w[
    Excavator Bulldozer Crane Loader Grader Compactor Concrete-Mixer
  ]},
  113 => { name: "Aviation & Aircraft", icon: "airplane", subs: %w[
    Private-Plane Helicopter Drone Commercial-Aircraft Aircraft-Parts
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # PROPERTY (114-124)
  # ════════════════════════════════════════════════════════════════════════
  114 => { name: "Apartments & Flats for Rent", icon: "buildings", subs: %w[
    Studio 1-Bedroom 2-Bedroom 3-Bedroom Duplex Loft Serviced Penthouse
  ]},
  115 => { name: "Apartments & Flats for Sale", icon: "buildings", subs: %w[
    Studio 1-Bedroom 2-Bedroom 3-Bedroom Duplex Loft Serviced Penthouse
  ]},
  116 => { name: "Houses & Villas for Sale", icon: "house", subs: %w[
    Detached Semi-Detached Terraced Bungalow Mansion Duplex Villa
  ]},
  117 => { name: "Houses & Villas for Rent", icon: "house", subs: %w[
    Detached Semi-Detached Terraced Bungalow Mansion Duplex Villa
  ]},
  118 => { name: "Commercial Real Estate", icon: "storefront", subs: %w[
    Shop Office-Warehouse Mall Kiosk Showroom Market-Stall
  ]},
  119 => { name: "Office Space", icon: "buildings", subs: %w[
    Coworking Private-Office Shared-Desk Virtual-Office Executive-Suite
  ]},
  120 => { name: "Warehouses & Storage", icon: "warehouse", subs: %w[
    Self-Storage Cold-Storage Distribution-Center Loading-Dock
  ]},
  121 => { name: "Land & Plots", icon: "map-pin", subs: %w[
    Residential Commercial Agricultural Industrial Mixed-Use
  ]},
  122 => { name: "Short Lets & Vacation Rentals", icon: "house-line", subs: %w[
    Apartment-Villa Beach-House Guest-House Chalet Cabin
  ]},
  123 => { name: "Event Spaces & Venues", icon: "confetti", subs: %w[
    Banquet-Hall Conference-Room Outdoor-Venue Gallery Rooftop Garden
  ]},
  124 => { name: "Industrial Property", icon: "factory", subs: %w[
    Factory Workshop Plant Yard Garage
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # ELECTRONICS & TECH (125-137)
  # ════════════════════════════════════════════════════════════════════════
  125 => { name: "Smartphones", icon: "device-mobile", subs: %w[
    Apple Samsung Google Xiaomi OnePlus Nokia Vivo Realme Oppo Tecno Infinix
  ]},
  126 => { name: "Feature Phones", icon: "device-mobile", subs: %w[
    Button-Phone Rugged-Phone Senior-Phone KaiOS-Smart
  ]},
  127 => { name: "Tablets & iPads", icon: "device-tablet", subs: %w[
    Apple Samsung Xiaomi Lenovo Amazon-Fire Drawing-Tablet Kids-Tablet
  ]},
  128 => { name: "Laptops & Notebooks", icon: "laptop", subs: %w[
    Gaming Ultrabook Business Budget Chromebook 2-in-1 Workstation MacBook
  ]},
  129 => { name: "Desktop Computers", icon: "monitor", subs: %w[
    Gaming-PC Business-PC All-in-One Mini-PC Workstation
  ]},
  130 => { name: "Computer Components", icon: "cpu", subs: %w[
    Processor GPU Motherboard RAM SSD Hard-Drive PSU Cooling Case Monitor
  ]},
  131 => { name: "TV & Video Equipment", icon: "television", subs: %w[
    LED-TV Smart-TV Projector Monitor Streaming-Device DVD-Player Video-Wall
  ]},
  132 => { name: "Audio & Headphones", icon: "headphones", subs: %w[
    Over-Ear In-Ear Wireless Speaker Soundbar Subwoofer Microphone Amplifier
  ]},
  133 => { name: "Cameras & Photography", icon: "camera", subs: %w[
    DSLR Mirrorless Action-Cam Webcam Tripod Drone Lens Photo-Printer
  ]},
  134 => { name: "Wearable Technology", icon: "watch", subs: %w[
    Smartwatch Fitness-Band VR-Headset AR-Glasses Smart-Ring
  ]},
  135 => { name: "Video Game Consoles", icon: "game-controller", subs: %w[
    PlayStation Xbox Nintendo-Handheld Retro-Console Gaming-PC Handheld
  ]},
  136 => { name: "Video Games & Software", icon: "disc", subs: %w[
    PS5-Xbox-Switch-Games PC-Games Software-Licenses Game-Accessories Game-Controllers
  ]},
  137 => { name: "Smart Home Devices", icon: "house-line", subs: %w[
    Voice-Assistant Smart-Lock Smart-Camera Smart-Light Smart-Plug Smart-Thermostat Smart-Speaker Robot-Vacuum
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # FURNITURE & HOME (138-148)
  # ════════════════════════════════════════════════════════════════════════
  138 => { name: "Living Room Furniture", icon: "armchair", subs: %w[
    Sofa Coffee-Table TV-Stand Shelf Cabinet Recliner Ottoman
  ]},
  139 => { name: "Bedroom Furniture", icon: "bed", subs: %w[
    Bed-Frame Mattress Wardrobe Dresser Nightstand Headboard Mirror
  ]},
  140 => { name: "Kitchen & Dining Furniture", icon: "fork-knife", subs: %w[
    Dining-Table Chairs Kitchen-Cabinet Bar-Stool Island Bench
  ]},
  141 => { name: "Home Appliances", icon: "refrigerator", subs: %w[
    Refrigerator Washing-Machine Dryer Dishwasher Iron Generator Inverter AC-Fan Heater
  ]},
  142 => { name: "Kitchen Appliances", icon: "cooking-pot", subs: %w[
    Microwave Oven Blender Toaster Kettle Air-Fryer Cooker Food-Processor Juicer
  ]},
  143 => { name: "Lighting & Fixtures", icon: "lamp", subs: %w[
    Ceiling-Light Table-Lamp Floor-Lamp Chandelier Bulb LED-Strip Outdoor-Light
  ]},
  144 => { name: "Home Decor & Rugs", icon: "paint-brush-broad", subs: %w[
    Rug Carpet Curtain Wall-Art Vase Mirror Clock Frame
  ]},
  145 => { name: "Bedding & Bath", icon: "bed", subs: %w[
    Bedsheet Duvet Pillow Towel Bath-Mat Shower-Curtain Blanket
  ]},
  146 => { name: "Garden & Outdoor Living", icon: "tree", subs: %w[
    Lawn-Mower Garden-Chair Umbrella Flower-Pot Fence BBQ-Grill Hammock
  ]},
  147 => { name: "Tools & DIY Equipment", icon: "hammer", subs: %w[
    Power-Drill Hand-Tools Saw Wrench Screwdriver-Set Toolbox Measuring-Tools
  ]},
  148 => { name: "Security & Locks", icon: "lock-key", subs: %w[
    CCTV-Camera Padlock Door-Lock Alarm Safe Biometric-Smart-Lock Gate-Motor
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # FASHION & BEAUTY (149-160)
  # ════════════════════════════════════════════════════════════════════════
  149 => { name: "Men's Clothing", icon: "t-shirt", subs: %w[
    Shirts T-Shirts Trousers Jeans Shorts Suits Traditional-Wear Jackets Hoodies
  ]},
  150 => { name: "Men's Shoes", icon: "sneaker-move", subs: %w[
    Sneakers Formal Sandals Boots Loafers Slides Football-Boots
  ]},
  151 => { name: "Women's Clothing", icon: "t-shirt", subs: %w[
    Dresses Blouses Skirts Jeans Trousers Traditional-Wear Gowns Activewear Lingerie
  ]},
  152 => { name: "Women's Shoes", icon: "sneaker-move", subs: %w[
    Heels Sneakers Sandals Boots Flats Loafers Wedges
  ]},
  153 => { name: "Watches", icon: "watch", subs: %w[
    Analog Digital Smartwatch Luxury Sports Casual
  ]},
  154 => { name: "Jewelry & Accessories", icon: "ring", subs: %w[
    Rings Necklaces Bracelets Earrings Anklets Brooches Sets
  ]},
  155 => { name: "Bags & Luggage", icon: "backpack", subs: %w[
    Backpacks Handbags Luggage Wallets Messenger-Bags Clutches Travel-Bags
  ]},
  156 => { name: "Makeup & Cosmetics", icon: "flower-tulip", subs: %w[
    Foundation Lipstick Mascara Eyeshadow Concealer Blush Brushes-Sets
  ]},
  157 => { name: "Skincare", icon: "drop", subs: %w[
    Cream Serum Sunscreen Moisturizer Cleanser Toner Face-Mask
  ]},
  188 => { name: "Commercial Printing & Packaging", icon: "printer", subs: %w[
    Business-Cards Flyers Banners Labels Stickers Packaging-Boxes
  ]},
  158 => { name: "Fragrances & Perfumes", icon: "flower-tulip", subs: %w[
    Men-Women Unisex Body-Spray Oil-Perfume Gift-Sets
  ]},
  159 => { name: "Hair Care", icon: "scissors", subs: %w[
    Wigs Braids Weaves Relaxer Shampoo Extensions Natural-Hair-Products
  ]},
  160 => { name: "Health & Wellness Supplies", icon: "heart", subs: %w[
    Vitamins Supplements First-Aid Medical-Devices Fitness-Accessories Weight-Management
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # JOBS (161-171)
  # ════════════════════════════════════════════════════════════════════════
  161 => { name: "Software & IT Jobs", icon: "code", subs: %w[
    Frontend-Dev Backend-Dev Full-Stack DevOps Data-Scientist Mobile-Dev QA-Tester
  ]},
  162 => { name: "Sales & Marketing Jobs", icon: "chart-line-up", subs: %w[
    Sales-Rep Account-Manager Marketing-Manager Social-Media SEO-Specialist Content-Creator
  ]},
  163 => { name: "Accounting & Finance Jobs", icon: "coins", subs: %w[
    Accountant Auditor Financial-Analyst Tax-Consultant Payroll-Specialist
  ]},
  164 => { name: "Healthcare & Medical Jobs", icon: "stethoscope", subs: %w[
    Nurse Doctor Pharmacist Lab-Technician Physiotherapist Midwife
  ]},
  165 => { name: "Customer Service Jobs", icon: "headset", subs: %w[
    Call-Center Support-Agent Help-Desk Client-Relations
  ]},
  166 => { name: "Engineering Jobs", icon: "gear", subs: %w[
    Civil Mechanical Electrical Electronics Software Chemical Structural
  ]},
  167 => { name: "Education & Teaching Jobs", icon: "graduation-cap", subs: %w[
    Primary-Teacher Secondary-Teacher Lecturer Tutor Educational-Consultant
  ]},
  168 => { name: "Construction & Trades Jobs", icon: "hard-hat", subs: %w[
    Mason Carpenter Welder Plumber Electrician Painter Tiler
  ]},
  169 => { name: "Driver & Delivery Jobs", icon: "car", subs: %w[
    Truck-Driver Uber-Bolt-Drive Dispatch-Rider Delivery-Rider Logistics-Driver
  ]},
  170 => { name: "Hospitality & Tourism Jobs", icon: "airplane-landing", subs: %w[
    Chef Waiter Hotel-Staff Tour-Guide Bartender
  ]},
  171 => { name: "Remote & Freelance Opportunities", icon: "house-line", subs: %w[
    Freelance-Writing Graphic-Design Virtual-Assistant Video-Editing Transcription
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # SERVICES (172-182)
  # ════════════════════════════════════════════════════════════════════════
  172 => { name: "Home Cleaning & Repair", icon: "broom", subs: %w[
    Deep-Cleaning Fumigation Pest-Control Window-Cleaning Upholstery-Cleaning
  ]},
  173 => { name: "Plumbing & Electrical", icon: "wrench", subs: %w[
    Plumbing Electrical-Wiring Pipe-Fitting Geyser-Installation Fan-Installation
  ]},
  174 => { name: "Moving & Freight", icon: "truck", subs: %w[
    Home-Moving Office-Moving Freight-Fowarder Packing-Storage Container-Shipping
  ]},
  175 => { name: "Event Planning & Catering", icon: "confetti", subs: %w[
    Catering Event-Planning Decoration MC-Hire Equipment-Rental
  ]},
  176 => { name: "Photography & Videography", icon: "camera", subs: %w[
    Wedding-Photography Product-Photography Videography Drone-Shoot Photo-Editing
  ]},
  177 => { name: "Tutor & Classes", icon: "graduation-cap", subs: %w[
    Home-Tutor Online-Classes Language-Lessons Music-Lessons Coding-Classes
  ]},
  178 => { name: "Legal & Financial Services", icon: "scales", subs: %w[
    Lawyer Notary Tax-Advisory Loan-Broker Insurance-Agent
  ]},
  179 => { name: "IT & Web Development Services", icon: "code", subs: %w[
    Website-Dev App-Dev SEO Digital-Marketing Tech-Consulting
  ]},
  180 => { name: "Design & Creative Services", icon: "paint-brush-broad", subs: %w[
    Graphic-Design UI-UX Interior-Design Fashion-Design Logo-Design
  ]},
  181 => { name: "Beauty & Wellness Services", icon: "scissors", subs: %w[
    Hairdressing Barbering Nail-Tech Makeup-Artist Massage Spa-Treatment
  ]},
  182 => { name: "Car Repair & Detailing", icon: "wrench", subs: %w[
    Mechanic Car-Wash Detailing Panel-Beater AC-Repair Tire-Fitting
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # INDUSTRIAL & EQUIPMENT (183-191)
  # ════════════════════════════════════════════════════════════════════════
  183 => { name: "Heavy Industrial Machinery", icon: "gear", subs: %w[
    Generator Compressor Welding-Machine Crane lathe CNC-Machine
  ]},
  184 => { name: "Manufacturing Equipment", icon: "factory", subs: %w[
    Injection-Molding Packaging-Machine Cutting-Machine Filling-Machine Conveyor
  ]},
  185 => { name: "Agricultural Machinery & Tractors", icon: "tractor", subs: %w[
    Tractor Plough Harvester Thresher Irrigation-System
  ]},
  186 => { name: "Livestock & Farm Animals", icon: "dog", subs: %w[
    Cattle Goats Sheep Poultry Pigs Fish-Ponds
  ]},
  187 => { name: "Seeds, Crops & Produce", icon: "flower-tulip", subs: %w[
    Grains Vegetables Fruits Tubers Legumes Organic-Products
  ]},
  188 => { name: "Commercial Printing & Packaging", icon: "printer", subs: %w[
    Business-Cards Flyers Banners Labels Stickers Packaging-Boxes
  ]},
  189 => { name: "Restaurant & Catering Equipment", icon: "cooking-pot", subs: %w[
    Commercial-Oven Deep-Fryer Mixer Food-Warmer Refrigeration Display-Case
  ]},
  190 => { name: "Medical & Lab Equipment", icon: "stethoscope", subs: %w[
    Diagnostic Surgical Laboratory Dental Imaging Physiotherapy-Equipment
  ]},
  191 => { name: "Safety & Protective Gear", icon: "shield", subs: %w[
    Helmet Gloves Goggles Safety-Boots High-Vis-Vest Ear-Protection Fire-Extinguisher
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # PETS (192-198)
  # ════════════════════════════════════════════════════════════════════════
  192 => { name: "Dogs & Puppies", icon: "dog", subs: %w[
    German-Shepherd French-Bulldog Labrador Rottweiler Poodle Mixed-Breed Small-Breed
  ]},
  193 => { name: "Cats & Kittens", icon: "cat", subs: %w[
    Persian Siamese Maine-Coon Ragdoll British-Shorthair Mixed-Breed
  ]},
  194 => { name: "Birds & Parrots", icon: "bird", subs: %w[
    Parrot Canary Pigeon Finch Cockatiel Lovebird
  ]},
  195 => { name: "Fish & Aquariums", icon: "fish", subs: %w[
    Freshwater Saltwater Tropical Betta Goldfish Tank-Setup
  ]},
  196 => { name: "Pet Food & Nutrition", icon: "bone", subs: %w[
    Dog-Food Cat-Food Bird-Food Fish-Food Treats Supplements
  ]},
  197 => { name: "Pet Accessories & Toys", icon: "toy-brick", subs: %w[
    Leash-Collar Crate-Carrier Bed-Toys Grooming-Tools Aquarium-Accessories
  ]},
  198 => { name: "Pet Grooming & Services", icon: "scissors", subs: %w[
    Grooming Boarding Walking Training Veterinary
  ]},

  # ════════════════════════════════════════════════════════════════════════
  # SPORTS, RECREATION & GENERAL (199-206)
  # ════════════════════════════════════════════════════════════════════════
  199 => { name: "Fitness & Gym Equipment", icon: "dumbbell", subs: %w[
    Treadmill Dumbbell Barbell Kettlebell Bench Resistance-Bands Yoga-Mat
  ]},
  200 => { name: "Bicycles & Cycling", icon: "bicycle", subs: %w[
    Road-Bike Mountain-Bike BMX E-Bike Tricycle Accessories
  ]},
  201 => { name: "Outdoor & Camping Gear", icon: "tent", subs: %w[
    Tent Sleeping-Bag Backpack Hiking-Boots Camping-Stove Water-Filter
  ]},
  202 => { name: "Musical Instruments", icon: "music-note", subs: %w[
    Guitar Piano/Keyboard Drums Violin Flute Saxophone Brass
  ]},
  203 => { name: "Books & Publications", icon: "book-open", subs: %w[
    Fiction Non-Fiction Textbooks Children-Books Comics Religious
  ]},
  204 => { name: "Board Games & Toys", icon: "toy-brick", subs: %w[
    Board-Games Puzzles Lego Action-Figures Dolls RC-Toys
  ]},
  205 => { name: "Art, Antiques & Collectibles", icon: "painting", subs: %w[
    Paintings Sculptures Pottery Antiques Handicrafts Coins-Stamps
  ]},
  206 => { name: "Ticket Sales & Events", icon: "ticket", subs: %w[
    Concerts Sports-Theatre Festivals Conferences Amusement-Parks
  ]},
}

created = 0
updated = 0

cats.each do |sort_order, data|
  slug = data[:name].parameterize

  parent = CommerceCategory.find_or_initialize_by(slug: slug)
  if parent.persisted?
    parent.update!(icon: data[:icon], sort_order: sort_order) if parent.icon.blank? || parent.sort_order != sort_order
    updated += 1
  else
    parent.update!(
      name: data[:name],
      icon: data[:icon],
      sort_order: sort_order,
      status: "active"
    )
    created += 1
  end

  (data[:subs] || []).each_with_index do |sub_name, idx|
    sub_slug = "#{slug}-#{sub_name.to_s.parameterize}"
    sub = CommerceCategory.find_or_initialize_by(slug: sub_slug)
    next if sub.persisted?

    sub.update!(
      name: sub_name.tr("-", " "),
      parent_id: parent.id,
      sort_order: idx,
      status: "active"
    )
    created += 1
  end
end

puts "Commerce categories: #{created} created, #{updated} existing"
