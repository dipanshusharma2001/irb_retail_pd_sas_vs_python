from src.config import *

# defining features in multiples categories
id_cols = ['id', 'issue_d', 'term']
loan_contract_cols = ["loan_amnt", "funded_amnt", "funded_amnt_inv", "int_rate", "installment", "grade", "sub_grade", "purpose", "verification_status"]
borrower_profile_cols = ['annual_inc', 'emp_length', 'emp_title', 'home_ownership', 'dti', 'delinq_2yrs', 'inq_last_6mths', 'open_acc', 
                         'pub_rec', 'revol_bal', 'revol_util', 'total_acc']

outcome_cols = ['loan_status', 'last_pymnt_d', 'last_pymnt_amnt', 'total_rec_prncp', 'total_rec_int', 'recoveries', 'collection_recovery_fee']

hardship_cols = ['hardship_flag', 'hardship_dpd', 'hardship_loan_status', 'debt_settlement_flag', 'settlement_status']



def save_as_pickle_if_not_exists_and_load(pickle_file_path)-> pd.DataFrame:
    """
    Save the DataFrame as a pickle file if it does not already exist.

    Parameters:
    df (pd.DataFrame): The DataFrame to save.
    pickle_file_path (str): The path to the pickle file.
    """
    if not os.path.exists(pickle_file_path):
        df = pd.read_csv(f"{pickle_file_path[:-4]}.csv", low_memory=False)
        df.to_pickle(pickle_file_path)
        print(f"Pickle file saved at: {pickle_file_path}")
    else:
        print(f"Pickle file already exists at: {pickle_file_path}")
        df = pd.read_pickle(pickle_file_path) 

    print(df.shape)

    # lowering the column names and removing spaces 
    df.columns =   df.columns.str.lower().str.replace(' ', '_')

    return df


def export_dict_to_excel(data_dict, file_path):
    """
    Export a dictionary of DataFrames to an Excel file, with each key as a sheet name.

    Parameters:
    data_dict (dict): A dictionary where keys are sheet names and values are DataFrames.
    file_path (str): The path to save the Excel file.

    Returns:
    None
    """
    with pd.ExcelWriter(file_path, engine='xlsxwriter') as writer:
        for sheet_name, df in data_dict.items():
            if not isinstance(df, pd.DataFrame):
                raise ValueError(f"Value for sheet '{sheet_name}' is not a DataFrame")
            df.to_excel(writer, sheet_name=sheet_name, index=False)
    print(f"Excel file saved at: {file_path}")


# SFA functions
def WOE(df, feature, target)->pd.DataFrame:
    """
    Function to calculate Weight of Evidence (WOE) for a given feature.
    """
    temp = df[[feature, target]].copy()
    
    # filling missing as 'missing'
    temp[feature] = np.where(temp[feature].isna(), 'missing', temp[feature])
    
    temp = temp.groupby(feature).agg({target: ['count', 'sum']})
    temp.reset_index(inplace=True)

    result = pd.DataFrame()
    result[feature] = temp[feature]
    result['pop'] = temp[(target, 'count')]
    result['def'] = temp[(target, 'sum')]
    result['nondef'] = result['pop'] - result['def']
    result['def_rate'] = result['def'] / result['pop']
    result['perc_def'] = result['def'] / result['def'].sum()
    result['perc_nondef'] = result['nondef'] / result['nondef'].sum()
    result['woe'] = np.where((result['perc_def'] != 0) & (result['perc_nondef'] != 0), np.log(result['perc_nondef'] / result['perc_def']), np.nan)
    result['iv'] = np.where(result['woe'] != np.nan, (result['perc_nondef'] - result['perc_def']) * result['woe'], np.nan)

    return result

def WOE_PLOT(woe_summary: pd.DataFrame, x: str, y : str, figsize: tuple = (8, 4), rotation_angle: int = 0, font_size: int = 8)-> plt.figure:

    # plotting WOE values
    fig = plt.figure(figsize=figsize)
    sns.barplot(x=x, y=y, data=woe_summary)
    plt.title(f'Weight of Evidence (WOE) for {x}')
    plt.xlabel(x)
    plt.ylabel('WOE')
    plt.xticks(rotation=rotation_angle)
    # setting font size for x and y ticks
    plt.xticks(fontsize=8)
    plt.yticks(fontsize=8)

    return fig


def MonotonicBinning(data: pd.DataFrame, x: str, y: str, n_bins: int = 5) -> pd.DataFrame:

    temp = data[[x, y]].copy()
    X = temp[x].values.reshape(-1, 1)
    y_arr = temp[y].values

    # fitting isotonic regression
    iso = IsotonicRegression(increasing="auto")
    temp[f"{x}_iso"] = iso.fit_transform(X, y_arr)

    # discretizing isotonic output into bins
    temp[f"{x}_bin"] = pd.qcut(temp[f"{x}_iso"], q=n_bins, duplicates="drop")

    # creating bin mapping using original x
    bin_map = temp.groupby(f"{x}_bin")[x].agg(min_val="min", max_val="max").reset_index().sort_values('min_val').reset_index(drop=True)
    bin_map[f"{x}_bin_id"] = bin_map.index

    # creating the readable category
    bin_map[f"{x}_category"] = bin_map["min_val"].round(2).astype(str) + " - " + bin_map["max_val"].round(2).astype(str)
    
    orig_index = temp.index
    temp = pd.merge(temp.reset_index(drop=False), bin_map[[f"{x}_bin", f"{x}_bin_id", f"{x}_category"]], on=f"{x}_bin", how="left")
    temp.set_index(orig_index, inplace=True)

    return temp


# MFA functions
def violates_exclusion(combo, excluded_pairs)-> bool:
    combo = set(combo)
    for a, b in excluded_pairs:
        if a in combo and b in combo:
            return True
    return False

def violates_categories(combo, num_vars, cat_vars)-> bool:

    # variable type constraint
    n_num = sum(v in num_vars for v in combo)
    n_cat = sum(v in cat_vars for v in combo)

    if (n_num < 2 or n_cat < 2):
        return True
    
    return False

def compute_vif(X)-> pd.DataFrame:
    vif_df = pd.DataFrame()
    vif_df['variable'] = X.columns
    vif_df['vif'] = [variance_inflation_factor(X.values, i) for i in range(X.shape[1])]
    return vif_df


def run_mfa_combination(model_df, vars_list):

    # FORCE local writable copies
    X = sm.add_constant(model_df[vars_list]).copy()
    y = model_df['default_flag'].copy()

    try:
        model = sm.Logit(y, X).fit(disp=0)
    except:
        return pd.DataFrame()

    coef = model.params[vars_list]
    pvals = model.pvalues[vars_list]

    vif_df = compute_vif(X[vars_list])
    max_vif = vif_df['vif'].max()

    # FORCE writable prediction array
    y_pred = model.predict(X).copy()
    gini = 2 * roc_auc_score(y, y_pred) - 1

    corr = model_df[vars_list].corrwith(y)
    sign_check = np.all(np.sign(coef.values) == np.sign(corr.values))

    max_pval = pvals.max()

    if (max_pval < 0.05) and (max_vif < 2.5) and sign_check:

        # ---- contribution calculation ----
        stds = model_df[vars_list].std()
        abs_contrib = (coef.abs() * stds)
        contrib_pct = abs_contrib / abs_contrib.sum()

        result = pd.DataFrame({
            'variable': vars_list,
            'coefficients': coef.values,
            'p_values': pvals.values,
            'contribution_pct': contrib_pct.values
        })

        result = result.merge(vif_df, on='variable', how='left')
        result['max_pval'] = max_pval
        result['max_vif'] = max_vif
        result['gini'] = gini
        result['sign_check'] = sign_check
        result['min_contribution'] = contrib_pct.min()
        result['max_contribution'] = contrib_pct.max()

        return result

    return pd.DataFrame()