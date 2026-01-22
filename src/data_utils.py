from src.config import *

# defining features in multiples categories
id_cols = ['id', 'issue_d', 'term']
loan_contract_cols = ["loan_amnt", "funded_amnt", "funded_amnt_inv", "int_rate", "installment", "grade", "sub_grade", "purpose", "verification_status"]
borrower_profile_cols = ['annual_inc', 'emp_length', 'emp_title', 'home_ownership', 'dti', 'delinq_2yrs', 'inq_last_6mths', 'open_acc', 
                         'pub_rec', 'revol_bal', 'revol_util', 'total_acc']

outcome_cols = ['loan_status', 'last_pymnt_d', 'last_pymnt_amnt', 'total_rec_prncp', 'total_rec_int', 'recoveries', 'collection_recovery_fee']

hardship_cols = ['hardship_flag', 'hardship_dpd', 'hardship_loan_status', 'debt_settlement_flag', 'settlement_status']



def save_as_pickle_if_not_exists_and_load(pickle_file_path):
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