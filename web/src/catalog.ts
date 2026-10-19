import type { EntityKind } from './types'

// Selección inicial para las paletas; cualquier otro modelo se puede escribir a mano.
export const CATALOG: Partial<Record<EntityKind, { model: string; label: string }[]>> = {
  ped: [
    { model: 'a_m_y_hipster_01', label: 'Hipster (M)' },
    { model: 'a_f_y_hipster_01', label: 'Hipster (F)' },
    { model: 'a_m_m_business_01', label: 'Business (M)' },
    { model: 'a_f_y_business_01', label: 'Business (F)' },
    { model: 'a_m_y_beach_01', label: 'Beach (M)' },
    { model: 'a_f_y_beach_01', label: 'Beach (F)' },
    { model: 's_m_y_cop_01', label: 'Police officer' },
    { model: 's_m_m_paramedic_01', label: 'Paramedic' },
    { model: 's_m_y_bouncer_01', label: 'Bouncer' },
    { model: 'a_m_y_clubcust_01', label: 'Club goer (M)' },
    { model: 'a_f_y_clubcust_01', label: 'Club goer (F)' },
    { model: 'g_m_y_ballaorig_01', label: 'Ballas' },
    { model: 'g_m_y_famca_01', label: 'Families' },
  ],
  vehicle: [
    { model: 'elegy', label: 'Elegy RH8' },
    { model: 'sultan', label: 'Sultan' },
    { model: 'adder', label: 'Adder' },
    { model: 'baller', label: 'Baller' },
    { model: 'police', label: 'Police Cruiser' },
    { model: 'ambulance', label: 'Ambulance' },
    { model: 'taxi', label: 'Taxi' },
    { model: 'mule', label: 'Mule' },
    { model: 'bmx', label: 'BMX' },
    { model: 'bati', label: 'Bati 801' },
  ],
  prop: [
    { model: 'prop_chair_01a', label: 'Chair' },
    { model: 'prop_table_03', label: 'Table' },
    { model: 'prop_bench_01a', label: 'Bench' },
    { model: 'prop_barrier_work05', label: 'Barrier' },
    { model: 'prop_roadcone02a', label: 'Traffic cone' },
    { model: 'prop_speaker_06', label: 'Speaker' },
    { model: 'prop_tool_box_04', label: 'Toolbox' },
    { model: 'prop_bbq_1', label: 'BBQ' },
    { model: 'prop_parasol_04b', label: 'Parasol' },
    { model: 'prop_mic_01', label: 'Microphone' },
  ],
}

export const WEATHERS = [
  'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'OVERCAST', 'RAIN', 'CLEARING', 'THUNDER',
  'SMOG', 'FOGGY', 'XMAS', 'SNOW', 'SNOWLIGHT', 'BLIZZARD', 'HALLOWEEN', 'NEUTRAL',
]

export const VEHICLE_DOORS = ['Front L', 'Front R', 'Rear L', 'Rear R', 'Hood', 'Trunk']
