"""Build the bundled subset from USDA SR Legacy ASCII (CC0), without API keys.
Usage: python3 Scripts/build_nutrition_catalogue.py /path/to/SR-Leg_ASC.zip
Archive: https://ndownloader.figshare.com/files/43633731
Metadata: https://catalog.data.gov/dataset/usda-national-nutrient-database-for-standard-reference-legacy-release
The generated file is committed; this script never runs inside the app.
"""
import csv
import io
import json
import sys
from pathlib import Path
from zipfile import ZipFile

archive = ZipFile(sys.argv[1])
def rows(name):
    return csv.reader(io.StringIO(archive.read(name).decode('latin1')), delimiter='^', quotechar='~')
food_names = {row[0]: row[2] for row in rows('FOOD_DES.txt')}
keys = {'208': 'calories', '203': 'protein', '205': 'carbohydrates', '204': 'fat', '291': 'fibre', '269': 'sugar', '606': 'saturatedFat', '307': 'sodium'}
nutrients = {}
for row in rows('NUT_DATA.txt'):
    if row[1] in keys:
        nutrients.setdefault(row[0], {})[keys[row[1]]] = float(row[2])
weights = {}
for row in rows('WEIGHT.txt'):
    if row[4]:
        grams = float(row[4])
        weights.setdefault(row[0], []).append({'id': 'usda-portion-' + row[1], 'title': f'{row[2]} {row[3]} ({grams:g} g)', 'baseAmount': grams})
# Names are simplified for discovery; each record retains the exact original description.
selection = [
('20045','White rice, cooked','chawal bhaat rice cooked'),('20044','White rice, raw','dry rice chawal'),
('20037','Brown rice, cooked','brown chawal'),('20036','Brown rice, raw','dry brown rice'),
('16070','Lentils, boiled, no salt','masoor dal cooked plain'),('16102','Pigeon peas, boiled, no salt','toor arhar dal cooked plain'),
('16081','Mung beans, boiled, no salt','moong dal cooked plain'),('16084','Urad beans, boiled, no salt','black gram dal cooked plain'),
('16083','Urad beans, raw','urad black gram dry'),('16101','Pigeon peas, raw','toor arhar dal dry'),
('16080','Mung beans, raw','moong dal dry'),('16057','Chickpeas, boiled, no salt','chana chole chickpea cooked'),
('16056','Chickpeas, raw','chana dry'),('16033','Red kidney beans, boiled, no salt','rajma cooked plain'),
('16032','Red kidney beans, raw','rajma dry'),('16015','Black beans, boiled, no salt','black bean cooked'),
('20080','Whole-wheat flour','atta wheat flour'),('20081','All-purpose flour','maida flour'),
('16157','Chickpea flour','besan gram flour'),('20061','Rice flour','chawal atta'),
('20466','Semolina, dry','sooji suji rava'),('08120','Oats, dry','rolled oatmeal'),
('08121','Oatmeal, cooked with water','oats porridge no salt'),('20137','Quinoa, cooked','quinoa'),
('20035','Quinoa, dry','uncooked quinoa'),('20032','Millet, cooked','bajra millet'),('20031','Millet, raw','bajra dry'),
('20006','Pearl barley, cooked','jau barley'),('20121','Pasta, cooked, no added salt','pasta'),
('18075','Whole-wheat bread, commercially prepared','brown bread slice'),('18069','White bread, commercially prepared','bread slice'),
('28306','Roti / chapati, commercially prepared','roti chapati phulka'),('28307','Naan, commercially prepared','naan plain'),
('28286','Paratha, commercial frozen whole-wheat','paratha'),
('01129','Egg, hard-boiled','anda egg boiled'),('01123','Egg, raw','anda'),('01128','Egg, fried','fried anda'),
('01132','Egg, scrambled','scrambled anda'),('05064','Chicken breast, roasted, meat only','chicken cooked boneless'),
('05057','Chicken breast, raw, meat and skin','chicken raw with skin'),
('15237','Atlantic salmon, farmed, cooked','salmon fish'),('15121','Tuna, canned in water, drained','tuna fish'),
('16126','Firm tofu','tofu soy'),('01116','Plain whole-milk yogurt','curd dahi yogurt'),
('01117','Plain low-fat yogurt','low fat curd dahi'),('01256','Plain nonfat Greek yogurt','greek yoghurt'),
('01077','Whole milk, 3.25% fat','doodh milk'),('01079','Milk, 2% fat','low fat milk doodh'),
('01085','Skim milk','skimmed fat free milk doodh'),('16120','Soymilk, original / vanilla, unfortified','soy milk'),
('01009','Cheddar cheese','cheese'),('01012','Creamed cottage cheese','cottage cheese not paneer'),
('01001','Salted butter','butter makkhan'),('01003','Anhydrous butter oil','ghee clarified butter'),
('04053','Olive oil','cooking oil'),('04060','Sunflower oil','cooking oil'),
('12061','Almonds','badam nuts'),('12087','Cashews, raw','kaju nuts'),('12155','English walnuts','akhrot nuts'),
('16087','Peanuts, raw','groundnut moongphali'),('16090','Peanuts, dry roasted, salted','groundnut moongphali roasted'),
('16098','Peanut butter, smooth, salted','peanut spread'),('12006','Chia seeds, dried','chia'),('12220','Flaxseed','alsi seeds'),
('09040','Banana, raw','kela fruit'),('09003','Apple, raw, with skin','seb apple'),('09200','Orange, raw','santra orange'),
('09176','Mango, raw','aam mango'),('09226','Papaya, raw','papita'),('09139','Guava, raw','amrood'),
('09266','Pineapple, raw','ananas'),('09326','Watermelon, raw','tarbooz'),('09421','Medjool dates','khajoor'),
('11365','Potato, boiled, no salt','aloo cooked'),('11352','Potato, raw, with skin','aloo raw'),
('11510','Sweet potato, boiled','shakarkandi'),('11457','Spinach, raw','palak raw'),('11458','Spinach, boiled, no salt','palak cooked'),
('11090','Broccoli, raw','broccoli'),('11091','Broccoli, boiled, no salt','broccoli cooked'),
('11124','Carrot, raw','gajar'),('11109','Cabbage, raw','patta gobi'),('11205','Cucumber, raw, with peel','kheera'),
('11282','Onion, raw','pyaz'),('11529','Tomato, raw','tamatar'),('11305','Green peas, boiled, no salt','matar cooked'),
('11136','Cauliflower, boiled, no salt','gobi cooked'),('11135','Cauliflower, raw','gobi raw'),
('11043','Mung bean sprouts, raw','moong sprouts'),('19335','White sugar','chini'),('19296','Honey','shahad')]
foods = []
for code, name, aliases in selection:
    assert code in food_names and 'calories' in nutrients[code], (code, name)
    foods.append(dict(id='usda-' + code, name=name, aliases=aliases, brand='', baseQuantity=100, baseUnit='g', values=nutrients[code], servings=weights.get(code, [])[:4], source='reference', sourceDetail=f'USDA SR Legacy, April 2018. NDB {code}. {food_names[code]}. Generic reference composition; choose the matching preparation and check current package labels.', sourceURL='https://fdc.nal.usda.gov/', incomplete=[], estimated=False, preparation=food_names[code]))
# Published manufacturer reference, not a claim about every paneer or current package.
foods.append(dict(id='label-amul-paneer', name='Amul Fresh Paneer (published reference)', aliases='paneer cottage cheese', brand='Amul / Dudhsagar Dairy', baseQuantity=100, baseUnit='g', values=dict(calories=312, protein=20, carbohydrates=4, fat=24, sugar=0, saturatedFat=14.4, sodium=24), servings=[], source='label', sourceDetail='Published approximate composition per 100 g from Dudhsagar Dairy, checked 24 Oct 2026. Verify your current pack; this does not describe every paneer.', sourceURL='https://dudhsagardairy.coop/dairy/products/amul-fresh-paneer/', incomplete=[], estimated=True, preparation='Brand-specific published paneer composition.'))
lookup={x['id']:x for x in foods}
def estimate(identifier,name,alias,ingredients,yield_g,servings,detail):
    vals={}
    for key in keys.values():
        values=[lookup[code]['values'].get(key) for code,amount in ingredients]
        if any(v is None for v in values): continue
        vals[key]=sum(v*amount/100 for v,(_,amount) in zip(values,ingredients))*100/yield_g
    named=[{'id':'dish-serving','title':f'1 {servings[0]} (~{servings[1]:g} g)','baseAmount':servings[1]}]
    foods.append(dict(id=identifier,name=name,aliases=alias,brand='',baseQuantity=100,baseUnit='g',values=vals,servings=named,source='estimate',sourceDetail=detail+' Calculated from the named reference ingredients and assumed finished yield. Cooking, water, salt and oil change actual values; correct your portion or save your own recipe.',sourceURL=None,incomplete=[],estimated=True,preparation=detail))
    lookup[identifier]=foods[-1]
estimate('estimate-roti','Homemade roti, no oil (estimate)','phulka chapati', [('usda-20080',30)],45,('piece',45),'One roti: 30 g atta; finished weight 45 g including water.')
estimate('estimate-paratha','Plain paratha (estimate)','parantha', [('usda-20080',30),('usda-04060',5)],60,('piece',60),'One paratha: 30 g atta and 5 g oil; finished weight 60 g.')
estimate('estimate-idli','Plain idli (estimate)','idly steamed', [('usda-20044',75),('usda-16083',25)],250,('idli',250/6),'Batch: 75 g raw rice and 25 g dry urad; assumed finished yield 250 g / 6 idlis. Fermentation changes are not modeled.')
estimate('estimate-dosa','Plain dosa (estimate)','dosai', [('usda-20044',75),('usda-16083',25),('usda-04060',10)],300,('dosa',100),'Batch: 75 g raw rice, 25 g dry urad and 10 g oil; assumed finished yield 300 g / 3 dosas.')
estimate('estimate-poha','Vegetable poha (estimate)','kanda pohe flattened rice', [('usda-20044',40),('usda-11282',20),('usda-11305',20),('usda-04060',5),('usda-16087',5)],160,('bowl',160),'Bowl: rice-equivalent composition for 40 g dry flakes, 20 g onion, 20 g peas, 5 g oil and 5 g peanuts; assumed finished yield 160 g. Flake composition is approximated by raw white rice.')
estimate('estimate-upma','Vegetable upma (estimate)','rava sooji suji', [('usda-20466',40),('usda-11124',30),('usda-11305',20),('usda-11282',20),('usda-04060',5)],200,('bowl',200),'Bowl: 40 g semolina, 30 g carrot, 20 g peas, 20 g onion and 5 g oil; finished yield 200 g.')
estimate('estimate-dal','Plain dal with tadka (estimate)','toor arhar cooked lentil', [('usda-16102',130),('usda-11529',20),('usda-11282',10),('usda-04060',3)],200,('bowl',200),'Bowl: 130 g boiled pigeon peas, 20 g tomato, 10 g onion and 3 g oil; finished yield 200 g. Added salt is not included.')
estimate('estimate-rajma','Rajma masala (estimate)','kidney bean curry', [('usda-16033',125),('usda-11529',30),('usda-11282',20),('usda-04060',5)],200,('bowl',200),'Bowl: 125 g boiled kidney beans, 30 g tomato, 20 g onion and 5 g oil; finished yield 200 g. Added salt is not included.')
estimate('estimate-chole','Chole masala (estimate)','chana chickpea curry', [('usda-16057',125),('usda-11529',30),('usda-11282',20),('usda-04060',5)],200,('bowl',200),'Bowl: 125 g boiled chickpeas, 30 g tomato, 20 g onion and 5 g oil; finished yield 200 g. Added salt is not included.')
estimate('estimate-khichdi','Vegetable khichdi (estimate)','khichadi rice dal', [('usda-20044',40),('usda-16080',20),('usda-11124',50),('usda-11305',50),('usda-04060',3)],350,('bowl',250),'Batch: 40 g raw rice, 20 g dry moong, 50 g carrot, 50 g peas and 3 g oil; assumed finished yield 350 g.')
estimate('estimate-sabzi','Mixed vegetable sabzi (estimate)','sabji curry', [('usda-11136',100),('usda-11124',50),('usda-11305',50),('usda-04060',5)],220,('bowl',150),'Batch: 100 g boiled cauliflower, 50 g carrot, 50 g peas and 5 g oil; finished yield 220 g. Added salt is not included.')
estimate('estimate-paneer-rice','Paneer rice bowl (estimate)','paneer chawal', [('usda-20045',200),('label-amul-paneer',100),('usda-11124',50),('usda-04060',5)],355,('bowl',355),'Bowl: 200 g cooked white rice, 100 g published-reference Amul paneer, 50 g carrot and 5 g oil. Brand and recipe may vary.')
# Salt is unmeasured in these estimates. Do not silently record it as zero.
for food in foods:
    if food['source']=='estimate': food['values'].pop('sodium',None)
out=Path(__file__).resolve().parents[1]/'FitOut/Resources/Nutrition/NutritionFoods.json'
out.write_text(json.dumps(foods,ensure_ascii=False,indent=2)+'\n')
print(f'{len(foods)} foods: {len(selection)} USDA references, 1 published label, 12 explicit recipe estimates; {out.stat().st_size:,} bytes')
