#!/usr/bin/env python3
"""Build data/freq_fr_1000.txt from the OpenSubtitles French frequency list
(PLAN2 §3.2: "seed from an open frequency list ... hand-checked for obvious junk").

Source: hermitdave/FrequencyWords fr_50k (surface forms + counts, spoken-register
corpus). This script turns surface forms into a ranked *lemma* list suitable for
vocab packs:

  1. drops grammar/function words (taught by the spine, not vocab material)
  2. maps conjugated verb forms to their infinitive (first-seen rank wins)
  3. drops subtitle noise: names, interjections, English bleed-through
  4. collapses plural/feminine inflections onto an already-seen base form

Output is deliberately larger than 1,000 entries: gen_vocab.py dedupes against
words already taught by v1 concepts and the conjugation module, then takes the
top 1,000 survivors (40 packs x 25 words).

Usage:
    python build_freq_list.py            # downloads source if missing, writes data/freq_fr_1000.txt
    python build_freq_list.py --top 1300
"""

import argparse
import re
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
DATA = HERE / "data"
RAW = DATA / "fr_50k_raw.txt"
OUT = DATA / "freq_fr_1000.txt"
SOURCE_URL = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/fr/fr_50k.txt"

# ---------------------------------------------------------------------------
# Grammar/function words: taught by the v1 spine and grammar lessons, not vocab.
STOP = set("""
de le la les l un une des du au aux à et ou où mais donc or ni car
que qui quoi dont qu je tu il elle on nous vous ils elles me te se
moi toi lui leur leurs eux soi y en ne n pas plus jamais rien personne
aucun aucune ce cet cette ces c ça cela ceci ci mon ma mes ton ta tes
son sa ses notre votre nos vos si oui non d j m s t
pour dans sur sous avec sans chez vers entre depuis pendant avant après
contre par comme quand comment pourquoi combien parce puis ensuite
tout tous toute toutes quelque quelques chaque plusieurs autre autres
même mêmes tel telle tels telles quel quelle quels quelles lequel laquelle
très trop peu beaucoup assez aussi encore déjà toujours enfin alors
ici là bas voilà voici bien sinon pourtant cependant ailleurs quelqu'un
celui celle ceux celles chacun chacune est-ce dès certains certaines importe
celui-ci celle-ci mien mienne tien tienne sien sienne nôtre vôtre lors puisque
afin parmi malgré selon envers etant étant desquels auxquels lorsque
deux trois quatre cinq six sept huit neuf dix onze douze treize quatorze
quinze seize vingt trente quarante cinquante soixante cent mille
premier première deuxième troisième
""".split())

# Interjections & subtitle noise (kept out; greetings like merci/bonjour stay in).
NOISE = set("""
oh ah eh hé ben bah hein euh hum ha hey ho hou ouf aïe oups hop pff
ouais ok okay allô hem mmm hmm mm ah-ah oh-oh na waouh wow
ta-ta tic tac bla vroom boum paf clic ca dollars pos
dr mr mme mlle mgr st ste ii iii iv vi ll ie ia ies heu km etre san
moi-même toi-même lui-même elle-même soi-même nous-mêmes vous-mêmes eux-mêmes
""".split())

# English bleed-through common in subtitle corpora.
ENGLISH = set("""
the you i to a it is my this that what well yeah yes no hi hello sir
man baby love mister miss lady boy girl please thank sorry good bye
fuck shit damn honey sweetie dear darling and will of in uh
""".split())

# Proper names frequent in subtitles. French homographs with real meanings
# (pierre = stone, rose = pink) are deliberately NOT listed.
NAMES = set("""
jack john tom sam joe charlie frank harry george michael mike david
nick danny jimmy johnny billy bobby eddie tony ray ben alex chris peter
james bill bob steve kate mary anna maria lisa sarah emma julie sophie
marie jean paul jacques louis henri hank walter jesse buzz max leo hugo
henry jim jane rick homer bart simpson batman superman
richard tommy amy ryan jake daniel robert lee mark adam martin charles
kevin grace dan larry brian eric jerry scott andy pete kim jason simon
al thomas carter emily luke ted matt sammy timmy ross rose-marie
new york london washington angeles california texas
""".split())

# Conjugated form -> infinitive. First-seen rank wins; later forms of the same
# lemma are folded in. The 20 conjugation-module verbs are mapped too (so their
# forms don't surface as junk lemmas); gen_vocab.py excludes those infinitives.
VERB_FORMS = {
    "être": "es est suis sont sommes êtes étais était étions étiez étaient été sera serai seras serez seront serais serait seraient serions sois soit soient soyez soyons fut",
    "avoir": "ai as a avons avez aviez ont avais avait avaient aura aurai auras aurez auront aurais aurait auriez aurions aie aies ait ayons ayez eu eue",
    "aller": "vais vas va allons allez vont allais allait allaient ira irai iras irez iront irait aille allé allée allés allées",
    "faire": "fais fait faites font faisais faisait faisaient fera ferai feras ferez feront ferais ferait fasse fassent faisons faite faits",
    "vouloir": "veux veut voulons voulez veulent voulais voulait vouliez voulaient voudra voudrai voudras voudrez voudront voudrais voudrait voulu veuillez veuille",
    "pouvoir": "peux peut pouvons pouvez peuvent pouvais pouvait pourra pourrai pourras pourrez pourront pourrais pourrait pourriez pourrions pu puisse",
    "devoir": "dois doit devons devez doivent devais devait devra devrai devrez devront devrais devrait dû due",
    "savoir": "sais sait savons savez saviez savent savais savait saura saurai saurez sauront saurais saurait su sache",
    "dire": "dis dit dites disent disais disait dira dirai direz diront dirais dirait disons dise",
    "voir": "vois voit voyez voient voyais voyait verra verrai verras verrez verront verrait voyons vu vus",
    "prendre": "prends prend prenez prennent prenais prenait prendra prendrai prendrez prendront pris prise prises",
    "venir": "viens vient venez viennent venais venait viendra viendrai viendras viendrez viendront venu venue venus vienne",
    "mettre": "mets met mettez mettent mettais mettait mettra mis mise mises",
    "parler": "parle parles parlez parlent parlais parlait parlera parlé",
    "aimer": "aime aimes aimez aiment aimais aimait aimera aimerais aimerait aimé aimée",
    "acheter": "achète achètes achetez achètent achetais acheté",
    "manger": "mange manges mangez mangent mangeais mangeait mangé",
    "partir": "pars part partez partent partais partait partira parti partie partis",
    "finir": "finis finit finissez finissent fini finie",
    "donner": "donne donnes donnez donnent donnais donnait donnera donné donnez-moi",
    # -- verbs beyond the conjugation module (vocab material) --
    "penser": "pense penses pensez pensent pensais pensait pensé",
    "croire": "crois croit croyez croient croyais croyait cru",
    "trouver": "trouve trouves trouvez trouvent trouvais trouvait trouvera trouvé trouvée",
    "chercher": "cherche cherches cherchez cherchent cherchais cherchait cherché",
    "attendre": "attends attend attendez attendent attendais attendait attendu",
    "regarder": "regarde regardes regardez regardent regardais regardait regardé",
    "écouter": "écoute écoutes écoutez écoutent écouté ecoute ecoutez",
    "arrêter": "arrête arrêtes arrêtez arrêtent arrêté arrêtée",
    "laisser": "laisse laisses laissez laissent laissé laissée",
    "passer": "passe passes passez passent passais passait passera passé passée",
    "rester": "reste restes restez restent restais restait resté",
    "arriver": "arrive arrives arrivez arrivent arrivais arrivait arrivera arrivé arrivée",
    "sortir": "sors sort sortez sortent sortais sortait sorti sortie",
    "entrer": "entre entrez entrent entré",
    "monter": "monte montez montent monté",
    "descendre": "descends descend descendez descendent descendu",
    "tomber": "tombe tombes tombez tombent tombé tombée",
    "vivre": "vis vit vivez vivent vivais vivait vécu",
    "tenir": "tiens tient tenez tiennent tenais tenait tenu",
    "sentir": "sens sent sentez sentent sentais sentait senti",
    "comprendre": "comprends comprend comprenez comprennent comprenais compris",
    "connaître": "connais connaît connait connaissez connaissent connaissais connu",
    "appeler": "appelle appelles appelez appellent appelais appelait appelé appelée",
    "demander": "demande demandes demandez demandent demandais demandait demandé",
    "oublier": "oublie oublies oubliez oublient oublié",
    "essayer": "essaie essaye essayez essaient essayé",
    "aider": "aide aides aidez aident aidé",
    "jouer": "joue joues jouez jouent jouais jouait joué",
    "gagner": "gagne gagnes gagnez gagnent gagné",
    "perdre": "perds perd perdez perdent perdu perdue",
    "payer": "paie paye payez paient payé",
    "travailler": "travaille travailles travaillez travaillent travaillais travaillait travaillé",
    "dormir": "dors dort dormez dorment dormi",
    "boire": "bois boit buvez boivent bu",
    "tuer": "tue tues tuez tuent tué tuée",
    "changer": "change changes changez changent changé",
    "marcher": "marche marches marchez marchent marché",
    "rentrer": "rentre rentrez rentrent rentré",
    "revenir": "reviens revient revenez reviennent revenu",
    "devenir": "deviens devient devenez deviennent devenu devenue",
    "porter": "porte portes portez portent porté",
    "montrer": "montre montres montrez montrent montré",
    "ouvrir": "ouvre ouvres ouvrez ouvrent ouvert ouverte",
    "fermer": "ferme fermes fermez ferment fermé fermée",
    "écrire": "écris écrit écrivez écrivent",
    "lire": "lis lit lisez lisent lu",
    "envoyer": "envoie envoies envoyez envoient envoyé",
    "recevoir": "reçois reçoit recevez reçoivent reçu",
    "rendre": "rends rend rendez rendent rendu",
    "répondre": "réponds répond répondez répondent répondu",
    "quitter": "quitte quittes quittez quittent quitté",
    "toucher": "touche touches touchez touchent touché",
    "garder": "garde gardes gardez gardent gardé",
    "sauver": "sauve sauvez sauvé sauvée",
    "manquer": "manque manques manquez manquent manqué",
    "adorer": "adore adores adorez adorent adoré",
    "détester": "déteste détestes détestez détestent détesté",
    "ressembler": "ressemble ressembles ressemblez ressemblent ressemblé",
    "espérer": "espère espères espérez espèrent espéré",
    "imaginer": "imagine imagines imaginez imaginent imaginé",
    "expliquer": "explique expliques expliquez expliquent expliqué",
    "décider": "décide décidez décident décidé",
    "choisir": "choisis choisit choisissez choisi",
    "utiliser": "utilise utilisez utilisent utilisé",
    "entendre": "entends entend entendez entendent entendu",
    "servir": "sers sert servez servent servi",
    "courir": "cours court courez courent couru",
    "suivre": "suit suivez suivent suivi",
    "mourir": "meurs meurt mourez meurent",
    "plaire": "plaît plait",
    "inquiéter": "inquiète inquiètes inquiétez",
    "excuser": "excuse excusez excusé",
    "asseoir": "assieds assied asseyez assis assise",
    "occuper": "occupe occupez occupé occupée",
    "apprendre": "apprends apprend apprenez apprennent appris",
    "agir": "agis agit agissez",
    "bouger": "bouge bouges bougez bougé",
    "rappeler": "rappelle rappelles rappelez rappelé",
    "ignorer": "ignore ignorez ignoré",
    "jurer": "jure jures jurez juré",
    "tirer": "tire tires tirez tiré tirée",
    "signifier": "signifie",
    "préférer": "préfère préfères préférez préféré",
    "retourner": "retourne retournes retournez retourné",
    "exister": "existe existent existé",
    "promettre": "promets promet promettez promis",
    "mentir": "mens ment mentez menti",
    "poser": "pose poses posez posé",
    "tourner": "tourne tournes tournez tourné",
    "intéresser": "intéresse intéressent intéressé",
    "apprécier": "apprécie appréciez apprécié",
    "mériter": "mérite méritez mérité",
    "parier": "parie pariez parié",
    "déranger": "dérange dérangez dérangé",
    "paraître": "paraît parait",
    "découvrir": "découvre découvrez découvert",
    "retrouver": "retrouve retrouves retrouvez retrouvé retrouvée",
    "voler": "vole voles volez volent volé volée",
    "épouser": "épouse épousez épousé",
    "enlever": "enlève enlevez enlevé",
    "arranger": "arrange arrangez arrangé",
    "prévoir": "prévois prévoit prévu",
    "foutre": "fous fout foutez foutu foutue",
    "amener": "amène amenez amené",
    "emmener": "emmène emmenez emmené",
    "ramener": "ramène ramenez ramené",
    "raconter": "raconte racontes racontez raconté",
    "assurer": "assure assurez assuré",
    "préparer": "prépare préparez préparé",
    "apporter": "apporte apportez apporté",
    "casser": "casse cassez cassé cassée",
    "frapper": "frappe frappez frappé",
    "rater": "rate ratez raté",
    "cacher": "cache cachez caché cachée",
    "accepter": "accepte acceptez accepté",
    "refuser": "refuse refusez refusé",
    "habiter": "habite habites habitez habité",
    "souhaiter": "souhaite souhaitez souhaité",
    "dépendre": "dépend dépends",
    "fonctionner": "fonctionne",
    "appartenir": "appartient appartiens",
    "concerner": "concerne",
    "pleurer": "pleure pleures pleurez pleuré",
    "regretter": "regrette regrettez regretté",
    "répéter": "répète répétez répété",
    "jeter": "jette jetez jeté jetée",
    "vendre": "vends vend vendez vendu vendue",
    "battre": "bats bat battez battu",
    "offrir": "offre offrez offert offerte",
    "grandir": "grandis grandit grandi",
    "signer": "signe signez signé signée",
    "vérifier": "vérifie vérifiez vérifié",
    "détruire": "détruis détruit détruisez détruite",
    "conduire": "conduis conduit conduisez",
    "lancer": "lance lancez lancé lancée",
    "chanter": "chante chantes chantez chanté",
    "respirer": "respire respirez respiré",
    "sonner": "sonne sonnez sonné",
    "craindre": "crains craint craignez",
    "coucher": "couche couches couchez couché couchée",
    "lever": "lève lèves levez levé levée",
    "virer": "vire virez viré virée",
    "engager": "engage engagez engagé engagée",
    "réaliser": "réalise réalisez réalisé réalisée",
    "diriger": "dirige dirigez dirigé",
    "tenter": "tente tentez tenté",
    "ressentir": "ressens ressent ressentez ressenti",
    "commencer": "commence commences commencez commencent commencé",
    "continuer": "continue continues continuez continuent continué",
    "compter": "compte comptes comptez comptent compté",
    "sembler": "semble semblez semblait",
    "supposer": "suppose supposez supposé",
    "valoir": "vaut valent valait",
    "prier": "prie pries priez",
    "suffire": "suffit",
    "souvenir_verbe": "souviens souvient souvenez",
    "falloir": "faut faudra fallait faudrait fallu",
}
# falloir & souvenir are grammar-lesson territory, not vocab lemmas.
DROP_LEMMAS = {"falloir", "souvenir_verbe"}

FORM_TO_LEMMA = {}
for lemma, forms in VERB_FORMS.items():
    FORM_TO_LEMMA[lemma if lemma not in DROP_LEMMAS else forms.split()[0]] = lemma
    for form in forms.split():
        FORM_TO_LEMMA.setdefault(form, lemma)

# Non-verb lemma rewrites: audible feminine adjectives (the strip-e rule can't
# reach these) and misc normalizations.
REWRITE = {
    "bonne": "bon", "belle": "beau", "nouvelle": "nouveau", "vieille": "vieux",
    "dernière": "dernier", "première": "premier", "prochaine": "prochain",
    "grosse": "gros", "folle": "fou", "gentille": "gentil", "longue": "long",
    "blanche": "blanc", "heureuse": "heureux", "sérieuse": "sérieux",
    "chère": "cher", "chérie": "chéri", "douce": "doux", "fraîche": "frais",
    "meilleure": "meilleur", "morte": "mort", "prête": "prêt",
    "mauvaise": "mauvais", "vraie": "vrai", "froide": "froid", "chaude": "chaud",
    "accord": "d'accord", "abord": "d'abord",
    "coeur": "cœur", "soeur": "sœur", "oeil": "œil", "oeuf": "œuf",
    "oeuvre": "œuvre", "noeud": "nœud", "voeu": "vœu",
    "ans": "an", "années": "année", "minutes": "minute", "enfants": "enfant",
    "bonnes": "bon", "petites": "petit", "nulle": "nul", "mesdames": "madame",
    "dernières": "dernier", "grandes": "grand", "belles": "beau", "beaux": "beau",
    "mauvaises": "mauvais", "ancienne": "ancien", "entière": "entier",
    "arrivés": "arriver", "amoureuse": "amoureux",
}

# Inversion/imperative clitics glued by hyphen (es-tu, laisse-moi, va-t-il).
CLITIC = re.compile(r".+-(?:t-)?(?:je|tu|il|elle|on|nous|vous|ils|elles|moi|toi|lui|leur|y|en|le|la|les|ce|là)$")
CLITIC_KEEP = {"rendez-vous"}

FRENCH_CHARS = set("abcdefghijklmnopqrstuvwxyzàâäçéèêëîïôöùûüÿœæ-'")


def keep(token):
    if len(token) < 2 or not set(token) <= FRENCH_CHARS:
        return False
    if token in STOP or token in NOISE or token in ENGLISH or token in NAMES:
        return False
    if token.startswith("-") or token.endswith("-") or token.endswith("'"):
        return False
    if CLITIC.match(token) and token not in CLITIC_KEEP:
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=1300, help="lemmas to emit (>1000 so gen_vocab can dedupe)")
    args = ap.parse_args()

    if not RAW.exists():
        DATA.mkdir(exist_ok=True)
        print(f"downloading {SOURCE_URL} ...")
        urllib.request.urlretrieve(SOURCE_URL, RAW)

    lemmas, seen = [], set()
    with open(RAW, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            token = parts[0].lower().replace("’", "'")
            if not keep(token):
                continue
            lemma = FORM_TO_LEMMA.get(token, token)
            lemma = REWRITE.get(lemma, lemma)
            if lemma in DROP_LEMMAS or lemma in seen:
                continue
            # collapse plural/feminine inflections onto an already-seen base
            base = lemma.rstrip("s")
            if base != lemma and base in seen:
                continue
            if len(lemma) > 3 and lemma.endswith("e") and lemma[:-1] in seen:
                continue
            seen.add(lemma)
            lemmas.append(lemma)
            if len(lemmas) >= args.top:
                break

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("# freq_fr_1000.txt — ranked French lemmas for the v2 vocab module (PLAN2 §3.2)\n")
        f.write(f"# Seeded from OpenSubtitles (hermitdave/FrequencyWords fr_50k), processed by\n")
        f.write(f"# build_freq_list.py, then hand-checked. {len(lemmas)} entries (> 1000 so\n")
        f.write("# gen_vocab.py can dedupe against v1 + conjugation-module words and still\n")
        f.write("# fill 40 packs x 25 words). Format: one lemma per line, rank = line order.\n")
        for lemma in lemmas:
            f.write(lemma + "\n")
    print(f"wrote {len(lemmas)} lemmas to {OUT.relative_to(HERE)}")
    print("hand-check reminder: review for names/noise that slipped the filters")


if __name__ == "__main__":
    main()
