BP="general hospitality best practice"
HAZ="https://www.osha.gov/hazcom"; BBP="https://www.osha.gov/bloodborne-pathogens"; LIFT="https://www.osha.gov/ergonomics"; SLIP="https://www.osha.gov/walking-working-surfaces"
HEAT="https://www.osha.gov/heat-exposure"; COLD="https://www.osha.gov/winter-weather"; EXIT="https://www.osha.gov/exit-routes"; FIRE="https://www.osha.gov/etools/evacuation-plans-procedures"
TOR="https://www.weather.gov/safety/tornado"; LIGHT="https://www.weather.gov/safety/lightning"; WIND="https://www.weather.gov/safety/cold-wind-chill-warning"
AED="https://www.redcross.org/take-a-class/aed/using-an-aed"; CPR="https://www.heart.org/en/cpr"; STROKE="https://www.stroke.org/en/about-stroke/stroke-symptoms"
CHOKE="https://www.redcross.org/take-a-class/resources/learn-first-aid/adult-child-choking"; BURN="https://www.mayoclinic.org/first-aid/first-aid-burns/basics/art-20056649"
ADA="https://www.ada.gov/resources/service-animals-2010-requirements/"; HT="https://www.dhs.gov/blue-campaign"; EEOC="https://www.eeoc.gov/harassment"
BRK="https://dli.mn.gov/breaks"; ESST="https://www.dli.mn.gov/sick-leave-FAQs"; WC="https://www.dli.mn.gov/workers-compensation"
OSHA_R="https://www.osha.gov/workers/file-complaint"; INJ="https://www.osha.gov/recordkeeping"; FA="https://www.osha.gov/medical-first-aid"
DOT="https://dps.mn.gov/divisions/ots"; HF="https://dps.mn.gov/divisions/ots/educational-materials/Pages/Hands-Free.aspx"; DVS="https://dps.mn.gov/divisions/dvs"
MDH="https://www.revisor.mn.gov/statutes/cite/169"; FMCSA="https://www.fmcsa.dot.gov/regulations"; NHTSA="https://www.nhtsa.gov/road-safety"
W8=["room_attendant","hk_supervisor","laundry","houseman","maintenance","breakfast","driver","bartender"]
HK=["room_attendant","hk_supervisor","houseman"]; RA=["room_attendant","hk_supervisor"]; LA=["laundry"]; HM=["houseman"]; DR=["driver"]
Q=[]
def add(roles,kind,rows):
    for r in rows: Q.append((roles,kind)+tuple(r))
