#%%
import os
from glob import glob
import re
import pandas as pd
import numpy as np
import json
from bs4 import BeautifulSoup
#%%
project_name = 'IFOCUS'
#base_dir = '/Users/xiaoqianxiao/projects'
base_dir = '/gscratch/scrubbed/fanglab/xiaoqian'
project_dir = os.path.join(base_dir, project_name)
file_dir = os.path.join(project_dir, 'derivatives/qc/mriqc')
func_output_name = os.path.join(file_dir, 'QC_func.csv')
anat_output_name = os.path.join(file_dir, 'QC_anat.csv')
sum_name = os.path.join(file_dir, 'sum.json')
#%%
import os
import re
from bs4 import BeautifulSoup
import pandas as pd

import os
import re
from bs4 import BeautifulSoup

# These will now be lists instead of dicts
import os
import re
from bs4 import BeautifulSoup

import os
import re
from bs4 import BeautifulSoup

import os
import re
from bs4 import BeautifulSoup

anat_iqm = []
func_iqm = []

for fname in os.listdir(file_dir):
    file_path = os.path.join(file_dir, fname)

    if not os.path.isfile(file_path) or not fname.lower().endswith('.html'):
        print(f"Skipping non-HTML file: {fname}")
        continue

    parts = fname.split('_')
    try:
        subID, sesID = parts[:2]
        modulID = parts[-1]
        rms_ID = parts[-2]
    except ValueError:
        print(f"Filename parsing error: {fname}")
        continue

    print(modulID)
    is_anat = 'T1w' in modulID
    is_func = 'bold' in modulID

    target = anat_iqm if is_anat else func_iqm if is_func else None

    if is_func and len(parts) > 4:
        taskID = re.split('[-]', parts[2])[1]
        runID = re.split('[-.]', parts[3])[1]
    else:
        taskID = None
        runID = None

    with open(file_path, 'r', encoding='utf-8', errors='ignore') as fh:
        soup = BeautifulSoup(fh.read(), 'html.parser')

    # Locate IQM table
    iqm_div = soup.find('div', id='about-metadata-2-collapse')
    table = iqm_div.find('table') if iqm_div else None

    if not table:
        # Fallback: find the first table with valid float values
        for t in soup.find_all('table'):
            for row in t.find_all('tr'):
                cols = row.find_all(['th', 'td'])
                if len(cols) >= 2:
                    try:
                        float(cols[-1].get_text(strip=True))
                        table = t
                        break
                    except ValueError:
                        continue
            if table:
                break

    if not table:
        print(f"No IQM table found in: {fname}")
        continue

    entry = {
        'subID': subID,
        'sesID': sesID,
        'modality': modulID
    }
    if is_func:
        entry.update({'taskID': taskID, 'runID': runID})

    for row in table.find_all('tr'):
        cols = row.find_all(['th', 'td'])
        if len(cols) < 2:
            continue
        name = "_".join(c.get_text(strip=True) for c in cols[:-1]).replace(" ", "_").lower()
        try:
            value = round(float(cols[-1].get_text(strip=True)), 5)
            entry[name] = value
        except ValueError:
            continue

    if target is not None:
        target.append(entry)

# Create and optionally save DataFrames
anat_df = pd.DataFrame(anat_iqm)
func_df = pd.DataFrame(func_iqm)
#print(anat_df.head())
print(func_df.head())

# save to CSV
#df_func.to_csv(func_output_name, index=False)
#df_anat.to_csv(anat_output_name, index=False)

#%%
df_structural = anat_df
df_functional = func_df

def numeric_column(df, column):
    return pd.to_numeric(df[column], errors='coerce')


def apply_thresholds(df, thresholds, label):
    available_conditions = []
    missing_metrics = []

    for metric, rule in thresholds.items():
        if metric not in df.columns:
            missing_metrics.append(metric)
            continue

        values = numeric_column(df, metric)
        operator = rule['operator']
        threshold_value = rule['value']

        if operator == '<':
            available_conditions.append(values < threshold_value)
        elif operator == '>':
            available_conditions.append(values > threshold_value)
        elif operator == '<=':
            available_conditions.append(values <= threshold_value)
        elif operator == '>=':
            available_conditions.append(values >= threshold_value)
        elif operator == 'between':
            available_conditions.append((values >= threshold_value[0]) & (values <= threshold_value[1]))
        elif operator == '~=':
            available_conditions.append((values - threshold_value).abs() < 0.1)

    if missing_metrics:
        print(f"Skipping missing {label} metric(s): {', '.join(missing_metrics)}")

    if not available_conditions:
        return pd.Series(False, index=df.index)

    return pd.concat(available_conditions, axis=1).any(axis=1)


# Apply thresholds
aqi_threshold = 0.2
if not df_functional.empty:
    functional_conditions = []

    if {'gsr_x', 'gsr_y'}.issubset(df_functional.columns):
        df_functional['gsr'] = df_functional[['gsr_x', 'gsr_y']].apply(pd.to_numeric, errors='coerce').max(axis=1)
        functional_conditions.append(numeric_column(df_functional, 'gsr') > 0.3)
    else:
        print("Skipping missing functional metric(s): gsr_x, gsr_y")

    for metric, cutoff in {'fd_mean': 0.5, 'fd_perc': 50, 'aqi': aqi_threshold}.items():
        if metric in df_functional.columns:
            functional_conditions.append(numeric_column(df_functional, metric) > cutoff)
        else:
            print(f"Skipping missing functional metric: {metric}")

    if functional_conditions:
        df_functional['Poor_Quality'] = pd.concat(functional_conditions, axis=1).any(axis=1)
    else:
        df_functional['Poor_Quality'] = False
else:
    df_functional['Poor_Quality'] = False
#df_functional['Poor_Quality'] = (df_functional['fd_mean'] > 0.5) | (df_functional['fd_perc'] > 50) | (df_functional['tsnr'] < 30) | (df_functional['aqi'] > aqi_threshold) | (df_functional['gsr'] > 0.3)
#%%
ori_thresholds = {
    #'cjv': {'operator': '>', 'value': 0.1}, #Coefficient of Joint Variation
    'cnr': {'operator': '<', 'value': 0.8}, #Contrast-to-Noise Ratio
    'efc': {'operator': '<=', 'value': 0.7}, #Entropy Focus Criterion
    #'fber': {'operator': '>=', 'value': 150}, #Foreground-to-Background Energy Ratio
    # 'fwhm_avg': {'operator': '>', 'value': 6.0}, #Full Width at Half Maximum (average)
    # 'fwhm_x': {'operator': '>', 'value': 6.0},
    # 'fwhm_y': {'operator': '>', 'value': 6.0},
    # 'fwhm_z': {'operator': '>', 'value': 6.0},
    #?'icvs_csf': {'operator': '<=', 'value': 0.2}, #Intracranial Volume Fractions
    #?'icvs_gm': {'operator': '>=', 'value': 0.4},
    #?'icvs_wm': {'operator': '>=', 'value': 0.4},
    #？'inu_med': {'operator': 'between', 'value': (0.8, 1.2)}, #Intensity Nonuniformity (Median)
    #？'inu_range': {'operator': '<', 'value': 0.3},
    'qi_1': {'operator': '>=', 'value': 0.1}, #Quality Index 1 (Ghosting/Artifacts)
    'qi_2': {'operator': '>=', 'value': 0.2}, #Quality Index 2 (Motion artifacts, usually scanner-specific)
    'rpve_csf': {'operator': '>=', 'value': 10}, #Relative Percent Volume Error for tissue segmentation
    'rpve_gm': {'operator': '>=', 'value': 10},
    'rpve_wm': {'operator': '>=', 'value': 10},
    'snr_csf': {'operator': '<=', 'value': 1.5}, #Signal-to-Noise Ratio (per tissue)
    'snr_gm': {'operator': '<=', 'value': 15},
    'snr_wm': {'operator': '<=', 'value': 15},
    'snr_total': {'operator': '<=', 'value': 15}
    #'snrd_csf': {'operator': '<=', 'value': 25}, #ignal-to-Noise Ratio Difference (per tissue)
    #'snrd_gm': {'operator': '<=', 'value': 25},
    #'snrd_wm': {'operator': '<=', 'value': 25},
    #'snrd_total': {'operator': '<=', 'value': 30},
    #?'summary_bg_k': {'operator': '~=', 'value': 0}, #Background kurtosis
    #?'summary_bg_mad': {'operator': '<', 'value': 10}, #Median Absolute Deviation of background intensity
    #?'summary_bg_mean': {'operator': '~=', 'value': 0}, #Mean intensity of the background
    #?'summary_csf_k': {'operator': '~=', 'value': 3},
    #?'summary_gm_mean': {'operator': '~=', 'value': 100},
    #?'summary_wm_mean': {'operator': '>', 'value': 100},
    #'tpm_overlap_csf': {'operator': '<', 'value': 0.7}, #Tissue Probability Map overlap (CSF, GM, WM)
    #'tpm_overlap_gm': {'operator': '<', 'value': 0.7},
    #'tpm_overlap_wm': {'operator': '<', 'value': 0.7},
    #'wm2max': {'operator': 'between', 'value': (0.6, 0.8)} #White Matter to Maximum intensity ratio
}
#%%
snr_gm_thresh = 15
if 'snr_gm' in df_structural.columns:
    snr_gm = numeric_column(df_structural, 'snr_gm')
    if snr_gm.notna().any():
        snr_gm_thresh = snr_gm.mean() - 2 * snr_gm.std()
else:
    print("Skipping data-driven snr_gm threshold because snr_gm is missing.")

thresholds = {
    'cnr': {'operator': '<', 'value': 0.8}, #Contrast-to-Noise Ratio
    #'efc': {'operator': '<=', 'value': 0.7}, #Entropy Focus Criterion
    'qi_1': {'operator': '>=', 'value': 0.1}, #Quality Index 1 (Ghosting/Artifacts)
    'qi_2': {'operator': '>=', 'value': 0.2}, #Quality Index 2 (Motion artifacts, usually scanner-specific)
    #'rpve_csf': {'operator': '>', 'value': 10}, #Relative Percent Volume Error for tissue segmentation
    #'rpve_gm': {'operator': '>', 'value': 10},
    #'rpve_wm': {'operator': '>', 'value': 10},
    'snr_csf': {'operator': '<', 'value': 1}, #Signal-to-Noise Ratio (per tissue)
    'snr_gm': {'operator': '<', 'value': snr_gm_thresh}, #Gray‐matter SNR usually sits around 10–30. A 15 threshold is stringent—it’ll catch many “mid‐range” scans. A cutoff of 10–12 is more common.
    'snr_wm': {'operator': '<', 'value': 5}
    #'snr_total': {'operator': '<', 'value': 10}
}

df_structural['Poor_Quality'] = apply_thresholds(df_structural, thresholds, 'structural')
#%%
# Extract excluded files
n_poor_quality_func = df_functional.loc[df_functional['Poor_Quality']==True,'subID'].shape[0]
n_poor_quality_structural = df_structural.loc[df_structural['Poor_Quality']==True,'subID'].shape[0]

results = {
    "Poor Quality Functional/Total Scans": f"{n_poor_quality_func}/{df_functional.shape[0]}",
    "Poor Quality Structural/Total Scans": f"{n_poor_quality_structural}/{df_structural.shape[0]}"
}

# Save to sum.json
with open(sum_name, "w") as f:
    json.dump(results, f, indent=4)
#%%
func_df.to_csv(func_output_name, index=False)
anat_df.to_csv(anat_output_name, index=False)
